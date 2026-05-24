import SwiftData
import SwiftUI

struct TripPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startsAt) private var trips: [Trip]

    @State private var showingTripEditor = false

    var body: some View {
        List {
            if trips.isEmpty {
                ContentUnavailableView("No Trips", systemImage: "suitcase.rolling")
            } else {
                ForEach(trips) { trip in
                    NavigationLink {
                        TripDetailView(trip: trip)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trip.title)
                                .font(.body.weight(.medium))
                            Text("\(Self.dateFormatter.string(from: trip.startsAt)) - \(Self.dateFormatter.string(from: trip.endsAt))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteTrips)
            }
        }
        .navigationTitle("Trips")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingTripEditor = true
                } label: {
                    Label("Add Trip", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingTripEditor) {
            NavigationStack {
                TripEditorView()
            }
        }
    }

    private func deleteTrips(at offsets: IndexSet) {
        for offset in offsets {
            modelContext.delete(trips[offset])
        }
        try? modelContext.save()
    }

    fileprivate static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}

private struct TripEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var startsAt = Date()
    @State private var endsAt = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var notes = ""
    @State private var laundryIntervalDays = 0
    @State private var wearsBeforeWash = 1

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .textInputAutocapitalization(.words)
            DatePicker("Start", selection: $startsAt, displayedComponents: .date)
            DatePicker("End", selection: $endsAt, displayedComponents: .date)
            TextEditor(text: $notes)
                .frame(minHeight: 96)

            Section("Laundry & Rewear") {
                Stepper(value: $laundryIntervalDays, in: 0...14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Laundry")
                        Text(laundryIntervalDays == 0 ? "No planned laundry" : "Every \(laundryIntervalDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $wearsBeforeWash, in: 1...5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wear before wash")
                        Text("\(wearsBeforeWash)x per clothing item")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Add Trip")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let trip = Trip(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            endsAt: maxDate(startsAt, endsAt),
            notes: notes,
            laundryIntervalDays: laundryIntervalDays,
            wearsBeforeWash: wearsBeforeWash
        )
        modelContext.insert(trip)
        try? modelContext.save()
        dismiss()
    }

    private func maxDate(_ first: Date, _ second: Date) -> Date {
        first > second ? first : second
    }
}

private struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var preferences: [StylePreference]

    @Bindable var trip: Trip
    @State private var showingStopEditor = false
    @State private var isGeneratingPackingList = false
    @State private var isGeneratingItinerary = false
    @State private var feedbackStatus = ""

    private let service = TripPlanningService()

    var body: some View {
        List {
            Section("Stops") {
                ForEach(trip.stops.sorted { $0.startsAt < $1.startsAt }) { stop in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stop.location)
                            .font(.body.weight(.medium))
                        Text("\(TripPlannerView.dateFormatter.string(from: stop.startsAt)) - \(TripPlannerView.dateFormatter.string(from: stop.endsAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !stop.expectedWeather.isEmpty {
                            Text(stop.expectedWeather)
                                .font(.caption)
                        }
                    }
                }
                Button {
                    showingStopEditor = true
                } label: {
                    Label("Add Stop", systemImage: "plus")
                }
            }

            Section("Laundry & Rewear") {
                Stepper(value: $trip.laundryIntervalDays, in: 0...14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Laundry")
                        Text(trip.laundryIntervalDays == 0 ? "No planned laundry" : "Every \(trip.laundryIntervalDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $trip.wearsBeforeWash, in: 1...5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Wear before wash")
                        Text("\(trip.wearsBeforeWash)x per clothing item")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Packing uses these values to reduce overpacking. It chooses enough items to cover the longest stretch between laundry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generate") {
                Button {
                    Task { @MainActor in
                        isGeneratingPackingList = true
                        await service.rebuildPackingList(for: trip, closet: closetItems, context: modelContext)
                        try? modelContext.save()
                        isGeneratingPackingList = false
                    }
                } label: {
                    Label(isGeneratingPackingList ? "Generating Packing List" : "Packing List", systemImage: "checklist")
                }
                .disabled(isGeneratingPackingList || trip.stops.isEmpty)

                Button {
                    Task { @MainActor in
                        isGeneratingItinerary = true
                        await service.rebuildItinerary(
                            for: trip,
                            closet: closetItems,
                            feedback: feedback,
                            stylePreference: preferences.first,
                            context: modelContext
                        )
                        try? modelContext.save()
                        isGeneratingItinerary = false
                    }
                } label: {
                    Label(isGeneratingItinerary ? "Generating Itinerary" : "Outfit Itinerary", systemImage: "calendar")
                }
                .disabled(isGeneratingItinerary || trip.stops.isEmpty)
            }

            ForEach(trip.packingLists) { list in
                Section(list.title) {
                    ForEach(list.items) { packingItem in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(packingItem.item?.name ?? "Item")
                                Spacer()
                                Text("x\(packingItem.quantity)")
                                    .foregroundStyle(.secondary)
                            }
                            if !packingItem.reason.isEmpty {
                                Text(packingItem.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Itinerary") {
                ForEach(trip.itineraryOutfits.sorted { $0.date < $1.date }) { itinerary in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(TripPlannerView.dateFormatter.string(from: itinerary.date)) - \(itinerary.location)")
                            .font(.body.weight(.medium))
                        if let outfit = itinerary.outfit {
                            Text(outfit.items.compactMap { $0.item?.name }.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let latestFeedback = latestFeedback(for: outfit) {
                                Text("Feedback: \(latestFeedback.type.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Button {
                                    recordFeedback(for: itinerary, type: .goodOutfit)
                                } label: {
                                    Label("Good", systemImage: "hand.thumbsup")
                                }
                                Button {
                                    recordFeedback(for: itinerary, type: .badOutfit)
                                } label: {
                                    Label("Bad", systemImage: "hand.thumbsdown")
                                }
                                Menu {
                                    Button("Bad for weather") {
                                        recordFeedback(for: itinerary, type: .badForWeather)
                                    }
                                    Button("Bad for context") {
                                        recordFeedback(for: itinerary, type: .badForOccasion)
                                    }
                                    Button("Colors do not work") {
                                        recordFeedback(for: itinerary, type: .colorsDoNotWork)
                                    }
                                    Button("Dislike combination") {
                                        recordFeedback(for: itinerary, type: .dislikeCombination)
                                    }
                                } label: {
                                    Label("Issue", systemImage: "exclamationmark.bubble")
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                if !feedbackStatus.isEmpty {
                    Text(feedbackStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(trip.title)
        .sheet(isPresented: $showingStopEditor) {
            NavigationStack {
                TripStopEditorView(trip: trip)
            }
        }
        .onChange(of: trip.laundryIntervalDays) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.wearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
    }

    private func recordFeedback(for itinerary: DailyItineraryOutfit, type: FeedbackType) {
        guard let outfit = itinerary.outfit else { return }
        let note = "Trip itinerary: \(trip.title), \(TripPlannerView.dateFormatter.string(from: itinerary.date))"
        let entry = Feedback(
            type: type,
            note: note,
            combinationKey: OutfitRecommendation.combinationKey(for: outfit.items.compactMap(\.item)),
            outfit: outfit
        )
        modelContext.insert(entry)
        outfit.feedback.append(entry)
        try? modelContext.save()
        feedbackStatus = "Saved \(type.displayName.lowercased()) feedback."
    }

    private func latestFeedback(for outfit: Outfit) -> Feedback? {
        feedback
            .filter { $0.outfit?.id == outfit.id }
            .sorted { $0.createdAt > $1.createdAt }
            .first
    }
}

private struct TripStopEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var trip: Trip
    @State private var location = ""
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var customsNotes = ""

    init(trip: Trip) {
        self.trip = trip
        _startsAt = State(initialValue: trip.startsAt)
        _endsAt = State(initialValue: trip.startsAt)
    }

    var body: some View {
        Form {
            TextField("Location", text: $location)
                .textInputAutocapitalization(.words)
            DatePicker("Start", selection: $startsAt, displayedComponents: .date)
            DatePicker("End", selection: $endsAt, displayedComponents: .date)
            TextField("Activities or local notes", text: $customsNotes)
                .textInputAutocapitalization(.sentences)
        }
        .navigationTitle("Add Stop")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let stop = TripStop(
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            endsAt: startsAt > endsAt ? startsAt : endsAt,
            expectedWeather: "",
            customsNotes: customsNotes,
            trip: trip
        )
        modelContext.insert(stop)
        trip.stops.append(stop)
        try? modelContext.save()
        dismiss()
    }
}
