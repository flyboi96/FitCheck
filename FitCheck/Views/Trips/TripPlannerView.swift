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

    var body: some View {
        Form {
            TextField("Title", text: $title)
                .textInputAutocapitalization(.words)
            DatePicker("Start", selection: $startsAt, displayedComponents: .date)
            DatePicker("End", selection: $endsAt, displayedComponents: .date)
            TextEditor(text: $notes)
                .frame(minHeight: 96)
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
        let trip = Trip(title: title.trimmingCharacters(in: .whitespacesAndNewlines), startsAt: startsAt, endsAt: maxDate(startsAt, endsAt), notes: notes)
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

            Section("Generate") {
                Button {
                    service.rebuildPackingList(for: trip, closet: closetItems, context: modelContext)
                    try? modelContext.save()
                } label: {
                    Label("Packing List", systemImage: "checklist")
                }

                Button {
                    service.rebuildItinerary(
                        for: trip,
                        closet: closetItems,
                        feedback: feedback,
                        stylePreference: preferences.first,
                        context: modelContext
                    )
                    try? modelContext.save()
                } label: {
                    Label("Outfit Itinerary", systemImage: "calendar")
                }
            }

            ForEach(trip.packingLists) { list in
                Section(list.title) {
                    ForEach(list.items) { packingItem in
                        HStack {
                            Text(packingItem.item?.name ?? "Item")
                            Spacer()
                            Text("x\(packingItem.quantity)")
                                .foregroundStyle(.secondary)
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
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.title)
        .sheet(isPresented: $showingStopEditor) {
            NavigationStack {
                TripStopEditorView(trip: trip)
            }
        }
    }
}

private struct TripStopEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var trip: Trip
    @State private var location = ""
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var expectedWeather = ""
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
            TextField("Expected weather", text: $expectedWeather)
                .textInputAutocapitalization(.sentences)
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
            expectedWeather: expectedWeather,
            customsNotes: customsNotes,
            trip: trip
        )
        modelContext.insert(stop)
        trip.stops.append(stop)
        try? modelContext.save()
        dismiss()
    }
}
