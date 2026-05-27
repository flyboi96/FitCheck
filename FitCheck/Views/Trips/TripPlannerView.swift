import SwiftData
import SwiftUI

struct TripPlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Trip.startsAt) private var trips: [Trip]

    @State private var showingTripEditor = false

    var body: some View {
        List {
            if trips.isEmpty {
                ContentUnavailableView(
                    "No Plans",
                    systemImage: "calendar.badge.plus",
                    description: Text("Plan travel packing or a week of outfits ahead of time.")
                )
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
        .navigationTitle("Plans")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingTripEditor = true
                } label: {
                    Label("Add Plan", systemImage: "plus")
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
    @State private var topWearsBeforeWash = 1
    @State private var bottomWearsBeforeWash = 3
    @State private var sweaterWearsBeforeWash = 3
    @State private var jacketWearsBeforeWash = 5
    @State private var activewearWearsBeforeWash = 1

    var body: some View {
        Form {
            Section("Plan") {
                TextField("Title", text: $title, prompt: Text("Rome trip or Work week outfits"))
                    .textInputAutocapitalization(.words)
                DatePicker("Start", selection: $startsAt, displayedComponents: .date)
                DatePicker("End", selection: $endsAt, displayedComponents: .date)
                TextEditor(text: $notes)
                    .frame(minHeight: 96)
                Text("Use this for travel, packing, or a normal week of planned outfits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Laundry & Rewear") {
                Stepper(value: $laundryIntervalDays, in: 0...14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Laundry")
                        Text(laundryIntervalDays == 0 ? "No planned laundry" : "Every \(laundryIntervalDays) days")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                wearStepper("Shirts", value: $topWearsBeforeWash)
                wearStepper("Pants / shorts", value: $bottomWearsBeforeWash)
                wearStepper("Sweaters", value: $sweaterWearsBeforeWash)
                wearStepper("Jackets", value: $jacketWearsBeforeWash)
                wearStepper("Exercise clothes", value: $activewearWearsBeforeWash)
            }
        }
        .navigationTitle("Add Plan")
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
            wearsBeforeWash: topWearsBeforeWash,
            topWearsBeforeWash: topWearsBeforeWash,
            bottomWearsBeforeWash: bottomWearsBeforeWash,
            sweaterWearsBeforeWash: sweaterWearsBeforeWash,
            jacketWearsBeforeWash: jacketWearsBeforeWash,
            activewearWearsBeforeWash: activewearWearsBeforeWash
        )
        modelContext.insert(trip)
        try? modelContext.save()
        dismiss()
    }

    private func maxDate(_ first: Date, _ second: Date) -> Date {
        first > second ? first : second
    }

    private func wearStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(value.wrappedValue)x before wash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TripPlanDay: Identifiable {
    var date: Date

    var id: TimeInterval {
        Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate
    }
}

private struct TripDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var preferences: [StylePreference]

    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @Bindable var trip: Trip
    @State private var showingStopEditor = false
    @State private var editingStop: TripStop?
    @State private var isGeneratingPackingList = false
    @State private var isGeneratingItinerary = false
    @State private var feedbackStatus = ""
    @State private var generationStatus = ""
    @State private var feedbackItinerary: DailyItineraryOutfit?
    @State private var editingItinerary: DailyItineraryOutfit?
    @State private var editingDayPlan: TripPlanDay?

    private let service = TripPlanningService()

    var body: some View {
        List {
            Section("Stops") {
                Text("Use stops for broad location ranges. Use Daily Plan below for exact outfit requests by date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(sortedStops) { stop in
                    Button {
                        editingStop = stop
                    } label: {
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
                            if !stop.customsNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(stop.customsNotes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteStops)
                Button {
                    showingStopEditor = true
                } label: {
                    Label("Add Stop", systemImage: "plus")
                }
            }

            Section("Daily Plan") {
                Text("Set where you will be and the exact outfit types you want for each date. When Daily Plan is filled in, itinerary generation uses only the selected outfit types for each date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(planDays) { day in
                    Button {
                        editingDayPlan = day
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(TripPlannerView.dateFormatter.string(from: day.date))
                                .font(.body.weight(.medium))
                            Text(locationLabel(for: day.date).isEmpty ? "Set location" : locationLabel(for: day.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            let contexts = requestedContexts(on: day.date)
                            Text(contexts.isEmpty ? "No outfits selected" : contexts.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(contexts.isEmpty ? .tertiary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
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

                wearStepper("Shirts", value: $trip.topWearsBeforeWash)
                wearStepper("Pants / shorts", value: $trip.bottomWearsBeforeWash)
                wearStepper("Sweaters", value: $trip.sweaterWearsBeforeWash)
                wearStepper("Jackets", value: $trip.jacketWearsBeforeWash)
                wearStepper("Exercise clothes", value: $trip.activewearWearsBeforeWash)

                Text("Packing uses these values to reduce overpacking. Daily underwear/socks are separate from exercise underwear/socks, so running and lifting gear can be packed from the right saved quantities.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generate") {
                Button {
                    Task { @MainActor in
                        isGeneratingPackingList = true
                        defer { isGeneratingPackingList = false }
                        generationStatus = "Generating packing list from your closet and trip stops."
                        await service.rebuildPackingList(for: trip, closet: closetItems, context: modelContext)
                        try? modelContext.save()
                        generationStatus = "Packing list updated with \(trip.packingLists.flatMap(\.items).count) item rows."
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingPackingList ? "Generating Packing List" : "Packing List",
                        systemImage: "checklist",
                        isLoading: isGeneratingPackingList
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingPackingList || trip.stops.isEmpty)

                Button {
                    Task { @MainActor in
                        isGeneratingItinerary = true
                        defer { isGeneratingItinerary = false }
                        generationStatus = tripAIOptions == nil
                            ? "Generating outfit itinerary with local scoring."
                            : "Generating outfit itinerary with AI filtering and local scoring."
                        await service.rebuildItinerary(
                            for: trip,
                            closet: closetItems,
                            feedback: feedback,
                            stylePreference: preferences.first,
                            context: modelContext,
                            aiOptions: tripAIOptions
                        )
                        await service.rebuildPackingList(for: trip, closet: closetItems, context: modelContext)
                        try? modelContext.save()
                        generationStatus = "Itinerary and packing list updated."
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingItinerary ? "Generating Itinerary" : itineraryButtonTitle,
                        systemImage: "calendar",
                        isLoading: isGeneratingItinerary
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeneratingItinerary || trip.stops.isEmpty)

                if isGeneratingItinerary {
                    ProgressView("Generating itinerary")
                        .controlSize(.regular)
                }

                FitCheckInlineStatus(
                    message: generationStatus,
                    isLoading: isGeneratingPackingList || isGeneratingItinerary
                )

                Text("For a normal week, add one stop for your city across the whole date range, then use Daily Plan to choose outfits for each date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export") {
                ShareLink(
                    item: packingListExportText,
                    subject: Text("\(trip.title) Packing List")
                ) {
                    Label("Share Packing List", systemImage: "square.and.arrow.up")
                }
                .disabled(trip.packingLists.isEmpty)

                ShareLink(
                    item: itineraryExportText,
                    subject: Text("\(trip.title) Outfit Itinerary")
                ) {
                    Label("Share Outfit Itinerary", systemImage: "calendar.badge.clock")
                }
                .disabled(trip.itineraryOutfits.isEmpty)

                Text("Packing and itinerary export separately as clean text so you can send, print, or save each one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(trip.packingLists) { list in
                Section(list.title) {
                    ForEach(list.items) { packingItem in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(packingTitle(for: packingItem))
                                Spacer()
                                Text("x\(packingItem.quantity)")
                                    .foregroundStyle(.secondary)
                            }
                            if packingItem.item != nil, !packingItem.reason.isEmpty {
                                Text(packingItem.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Itinerary") {
                Text("Feedback here is saved to the same outfit feedback system used by daily recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(trip.itineraryOutfits.sorted { $0.date < $1.date }) { itinerary in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(TripPlannerView.dateFormatter.string(from: itinerary.date)) - \(itinerary.location)")
                                .font(.body.weight(.medium))
                            if !itinerary.activity.isEmpty {
                                Text(itinerary.activity)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let outfit = itinerary.outfit {
                            RecommendationCard(
                                recommendation: recommendation(for: outfit),
                                onGood: { recordFeedback(for: itinerary, type: .goodOutfit) },
                                onBad: { recordFeedback(for: itinerary, type: .badOutfit) },
                                onFeedback: { feedbackItinerary = itinerary },
                                onEdit: { editingItinerary = itinerary }
                            )
                            if let latestFeedback = latestFeedback(for: outfit) {
                                Text("Feedback: \(latestFeedback.type.displayName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                Label("Quick Issue", systemImage: "exclamationmark.bubble")
                            }
                            .buttonStyle(.bordered)
                        } else {
                            ContentUnavailableView("No Outfit", systemImage: "tshirt")
                        }
                    }
                    .padding(.vertical, 4)
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
        .sheet(item: $editingStop) { stop in
            NavigationStack {
                TripStopEditorView(trip: trip, stop: stop)
            }
        }
        .sheet(item: $feedbackItinerary) { itinerary in
            OutfitFeedbackEditorView(title: "Itinerary Feedback") { type, note in
                recordFeedback(for: itinerary, type: type, note: note)
            }
        }
        .sheet(item: $editingItinerary) { itinerary in
            NavigationStack {
                ItineraryOutfitEditorView(itinerary: itinerary)
            }
        }
        .sheet(item: $editingDayPlan) { day in
            NavigationStack {
                TripDayPlanEditorView(
                    trip: trip,
                    date: day.date,
                    existingStop: dailyPlanStop(on: day.date),
                    fallbackLocation: locationLabel(for: day.date)
                )
            }
        }
        .onChange(of: trip.laundryIntervalDays) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.wearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.topWearsBeforeWash) { _, _ in
            trip.wearsBeforeWash = trip.topWearsBeforeWash
            try? modelContext.save()
        }
        .onChange(of: trip.bottomWearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.sweaterWearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.jacketWearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: trip.activewearWearsBeforeWash) { _, _ in
            try? modelContext.save()
        }
    }

    private var sortedStops: [TripStop] {
        trip.stops
            .filter { !isDailyPlanStop($0) }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var planDays: [TripPlanDay] {
        dates(from: effectivePlanStart, through: effectivePlanEnd).map(TripPlanDay.init)
    }

    private func requestedContexts(on date: Date) -> [OutfitContextOption] {
        dailyPlanStop(on: date)?.requestedContexts ?? []
    }

    private func locationLabel(for date: Date) -> String {
        var seen = Set<String>()
        let stops = locationStops(on: date)
        let locations = stops.compactMap { stop -> String? in
            let location = stop.location.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedLocationKey(location)
            guard !location.isEmpty, seen.insert(key).inserted else { return nil }
            return location
        }
        return locations.joined(separator: " -> ")
    }

    private func dailyPlanStop(on date: Date) -> TripStop? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return trip.stops.first { stop in
            Calendar.current.startOfDay(for: stop.startsAt) == startOfDay &&
                Calendar.current.startOfDay(for: stop.endsAt) == startOfDay &&
                isDailyPlanStop(stop)
        }
    }

    private func stops(on date: Date) -> [TripStop] {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return trip.stops
            .filter { stop in
                Calendar.current.startOfDay(for: stop.startsAt) <= startOfDay &&
                    Calendar.current.startOfDay(for: stop.endsAt) >= startOfDay
            }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private func locationStops(on date: Date) -> [TripStop] {
        let stops = stops(on: date)
        let broadStops = stops.filter { !isDailyPlanStop($0) }
        return broadStops.isEmpty ? stops : broadStops
    }

    private func isDailyPlanStop(_ stop: TripStop) -> Bool {
        if stop.isDailyPlanEntry {
            return true
        }

        let startsAt = Calendar.current.startOfDay(for: stop.startsAt)
        let endsAt = Calendar.current.startOfDay(for: stop.endsAt)
        return startsAt == endsAt && !stop.requestedContexts.isEmpty
    }

    private var effectivePlanStart: Date {
        ([trip.startsAt] + sortedStops.map(\.startsAt)).min() ?? trip.startsAt
    }

    private var effectivePlanEnd: Date {
        ([trip.endsAt] + sortedStops.map(\.endsAt)).max() ?? trip.endsAt
    }

    private func normalizedLocationKey(_ location: String) -> String {
        location
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func dates(from start: Date, through end: Date) -> [Date] {
        var result: [Date] = []
        var cursor = Calendar.current.startOfDay(for: start)
        let final = Calendar.current.startOfDay(for: end)

        while cursor <= final {
            result.append(cursor)
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func deleteStops(at offsets: IndexSet) {
        let targets = offsets.map { sortedStops[$0] }
        for stop in targets {
            trip.stops.removeAll { $0.id == stop.id }
            modelContext.delete(stop)
        }
        try? modelContext.save()
        generationStatus = "Stop deleted. Regenerate packing and itinerary when ready."
    }

    private func recommendation(for outfit: Outfit) -> OutfitRecommendation {
        OutfitRecommendation(
            title: outfit.name,
            items: outfit.items.compactMap(\.item),
            score: outfit.score,
            notes: outfit.notes.fitcheckLines
        )
    }

    private func recordFeedback(for itinerary: DailyItineraryOutfit, type: FeedbackType) {
        recordFeedback(for: itinerary, type: type, note: "")
    }

    private func recordFeedback(for itinerary: DailyItineraryOutfit, type: FeedbackType, note: String) {
        guard let outfit = itinerary.outfit else { return }
        let baseNote = "Trip itinerary: \(trip.title), \(TripPlannerView.dateFormatter.string(from: itinerary.date))"
        let fullNote = note.isEmpty ? baseNote : "\(baseNote) - \(note)"
        let entry = Feedback(
            type: type,
            note: fullNote,
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

    private var itineraryButtonTitle: String {
        tripAIOptions == nil ? "Outfit Itinerary" : "AI Outfit Itinerary"
    }

    private var tripAIOptions: TripAIOptions? {
        guard useAIProxy, let baseURL = configuredAIProxyURL else { return nil }
        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return TripAIOptions(
            client: BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token),
            styleDescription: styleDescription,
            recentFeedback: feedback.prefix(12).map(feedbackSummary)
        )
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var styleDescription: String {
        let currentWearerProfile = WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
        let wearerLine = currentWearerProfile == .unspecified ? nil : "Wearer profile: \(currentWearerProfile.displayName)"
        guard let preference = preferences.first else { return wearerLine ?? "" }
        return [
            wearerLine,
            preference.styleDescription,
            preference.favoriteLooks,
            preference.preferredColors,
            preference.preferredFit,
            "Temperature comfort: \(preference.temperatureSensitivity.displayName)",
            preference.statementPiecePreference.isEmpty ? nil : "Statement pieces: \(preference.statementPiecePreference)",
            preference.rules,
            preference.dislikedCombinations.isEmpty ? nil : "Avoid: \(preference.dislikedCombinations)"
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    private func feedbackSummary(_ entry: Feedback) -> String {
        [
            entry.type.displayName,
            entry.note,
            entry.item?.name
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
    }

    private func packingTitle(for item: PackingListItem) -> String {
        if let clothingName = item.item?.name {
            return clothingName
        }
        return item.reason.isEmpty ? "Packing item" : item.reason
    }

    private var packingListExportText: String {
        var lines = [
            "\(trip.title) Packing List",
            "\(TripPlannerView.dateFormatter.string(from: trip.startsAt)) - \(TripPlannerView.dateFormatter.string(from: trip.endsAt))",
            ""
        ]

        let broadStops = trip.stops
            .filter { !isDailyPlanStop($0) }
            .sorted(by: { $0.startsAt < $1.startsAt })
        if !broadStops.isEmpty {
            lines.append("Stops")
            for stop in broadStops {
                lines.append("- \(stop.location): \(TripPlannerView.dateFormatter.string(from: stop.startsAt)) - \(TripPlannerView.dateFormatter.string(from: stop.endsAt))")
                if !stop.expectedWeather.isEmpty {
                    lines.append("  Weather: \(stop.expectedWeather)")
                }
            }
            lines.append("")
        }

        let dailyPlanStops = trip.stops
            .filter(isDailyPlanStop)
            .sorted(by: { $0.startsAt < $1.startsAt })
        if !dailyPlanStops.isEmpty {
            lines.append("Daily Plan")
            for stop in dailyPlanStops {
                lines.append("- \(TripPlannerView.dateFormatter.string(from: stop.startsAt)): \(stop.location)")
                if !stop.requestedContexts.isEmpty {
                    lines.append("  Outfits: \(stop.requestedContexts.map(\.displayName).joined(separator: ", "))")
                }
            }
            lines.append("")
        }

        for list in trip.packingLists.sorted(by: { $0.createdAt < $1.createdAt }) {
            lines.append(list.title)
            for packingItem in list.items.sorted(by: { packingTitle(for: $0) < packingTitle(for: $1) }) {
                lines.append("- \(packingTitle(for: packingItem)) x\(packingItem.quantity)")
                if packingItem.item != nil, !packingItem.reason.isEmpty {
                    lines.append("  \(packingItem.reason)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private var itineraryExportText: String {
        var lines = [
            "\(trip.title) Outfit Itinerary",
            "\(TripPlannerView.dateFormatter.string(from: trip.startsAt)) - \(TripPlannerView.dateFormatter.string(from: trip.endsAt))",
            ""
        ]

        for itinerary in trip.itineraryOutfits.sorted(by: { $0.date < $1.date }) {
            lines.append("\(TripPlannerView.dateFormatter.string(from: itinerary.date)) - \(itinerary.location)")
            if !itinerary.activity.isEmpty {
                lines.append("Context: \(itinerary.activity)")
            }
            if let outfit = itinerary.outfit {
                lines.append("Score: \(Int(outfit.score))")
                if !outfit.weatherSummary.isEmpty {
                    lines.append("Weather: \(outfit.weatherSummary)")
                }
                for item in outfit.items.compactMap(\.item).sorted(by: { $0.category.displayName < $1.category.displayName }) {
                    lines.append("- \(item.category.displayName): \(item.name)")
                }
                if !outfit.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("Comments:")
                    for note in outfit.notes.fitcheckLines {
                        lines.append("- \(note)")
                    }
                }
            } else {
                lines.append("No outfit generated")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func wearStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper(value: value, in: 1...7) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text("\(value.wrappedValue)x before wash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ItineraryOutfitEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var preferences: [StylePreference]

    @Bindable var itinerary: DailyItineraryOutfit
    @State private var searchText = ""
    @State private var status = ""

    private let engine = OutfitRecommendationEngine()

    var body: some View {
        Form {
            if let outfit = itinerary.outfit {
                Section("Current Outfit") {
                    ForEach(outfit.items.sorted(by: itemLinkSort)) { link in
                        if let item = link.item {
                            HStack {
                                Label(item.name, systemImage: item.category.systemImageName)
                                Spacer()
                                Button(role: .destructive) {
                                    remove(link, from: outfit)
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }

                Section("Add Item") {
                    TextField("Search closet", text: $searchText)
                        .textInputAutocapitalization(.words)
                    ForEach(Array(addableItems(for: outfit).prefix(30))) { item in
                        Button {
                            add(item, to: outfit)
                        } label: {
                            HStack {
                                Label(item.name, systemImage: item.category.systemImageName)
                                Spacer()
                                Text(item.category.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Score") {
                    Text("Score \(Int(outfit.score))")
                        .font(.headline)
                    if !outfit.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DisclosureGroup("Why this scored this way") {
                            ForEach(outfit.notes.fitcheckLines, id: \.self) { note in
                                Label(note, systemImage: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        rescore(outfit)
                    } label: {
                        Label("Rescore Outfit", systemImage: "arrow.clockwise")
                    }
                    if !status.isEmpty {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                ContentUnavailableView("No Outfit", systemImage: "tshirt", description: Text("This itinerary row does not have an outfit to edit."))
            }
        }
        .navigationTitle("Edit Outfit")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func addableItems(for outfit: Outfit) -> [ClothingItem] {
        let selectedIDs = Set(outfit.items.compactMap { $0.item?.id })
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return closetItems
            .filter { $0.status == .active && !selectedIDs.contains($0.id) }
            .filter { search.isEmpty || searchableText(for: $0).localizedCaseInsensitiveContains(search) }
            .sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return categorySortIndex($0.category) < categorySortIndex($1.category)
            }
    }

    private func add(_ item: ClothingItem, to outfit: Outfit) {
        let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
        modelContext.insert(link)
        outfit.items.append(link)
        rescore(outfit)
        status = "Added \(item.name) and updated the score."
    }

    private func remove(_ link: OutfitItemLink, from outfit: Outfit) {
        let itemName = link.item?.name ?? "item"
        outfit.items.removeAll { $0.id == link.id }
        modelContext.delete(link)
        rescore(outfit)
        status = "Removed \(itemName) and updated the score."
    }

    private func rescore(_ outfit: Outfit) {
        let request = RecommendationRequest(
            weather: weatherInput(for: outfit),
            occasion: outfit.occasion,
            activity: outfit.activity,
            selectedItem: nil
        )
        let recommendation = engine.scoreExistingOutfit(
            items: outfit.items.compactMap(\.item),
            feedback: feedback,
            stylePreference: preferences.first,
            request: request,
            title: outfit.name
        )

        outfit.score = recommendation.score
        outfit.notes = recommendation.notes.joined(separator: "\n")
        try? modelContext.save()
    }

    private func weatherInput(for outfit: Outfit) -> WeatherInput {
        WeatherInput(
            temperatureF: inferredTemperature(from: outfit.weatherSummary),
            isRaining: outfit.weatherSummary.localizedCaseInsensitiveContains("rain") || outfit.weatherSummary.localizedCaseInsensitiveContains("storm"),
            windMph: inferredWind(from: outfit.weatherSummary),
            location: itinerary.location,
            humidityPercent: inferredHumidity(from: outfit.weatherSummary)
        )
    }

    private func inferredTemperature(from text: String) -> Double {
        text.split { !$0.isNumber }.compactMap { Double($0) }.first ?? 70
    }

    private func inferredWind(from text: String) -> Double {
        let numbers = text.split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }
        return numbers.count > 1 ? numbers[1] : 5
    }

    private func inferredHumidity(from text: String) -> Double? {
        let lowercased = text.lowercased()
        guard lowercased.contains("humid") || lowercased.contains("humidity") || lowercased.contains("%") else {
            return nil
        }
        return text.split { !$0.isNumber && $0 != "." }.compactMap { Double($0) }.last
    }

    private func searchableText(for item: ClothingItem) -> String {
        [
            item.name,
            item.brand,
            item.category.displayName,
            ClothingInference.color(for: item),
            ClothingInference.pattern(for: item),
            item.notes
        ]
        .joined(separator: " ")
    }

    private func itemLinkSort(_ first: OutfitItemLink, _ second: OutfitItemLink) -> Bool {
        guard let firstItem = first.item, let secondItem = second.item else {
            return first.item != nil
        }
        if firstItem.category == secondItem.category {
            return firstItem.name.localizedCaseInsensitiveCompare(secondItem.name) == .orderedAscending
        }
        return categorySortIndex(firstItem.category) < categorySortIndex(secondItem.category)
    }

    private func categorySortIndex(_ category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
    }
}

private struct TripDayPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var trip: Trip
    let date: Date
    private let existingStop: TripStop?

    @State private var location = ""
    @State private var expectedWeather = ""
    @State private var notes = ""
    @State private var selectedContextRawValues: Set<String>

    init(trip: Trip, date: Date, existingStop: TripStop?, fallbackLocation: String) {
        self.trip = trip
        self.date = Calendar.current.startOfDay(for: date)
        self.existingStop = existingStop
        let fallback = fallbackLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        _location = State(initialValue: fallback.isEmpty ? existingStop?.location ?? "" : fallback)
        _expectedWeather = State(initialValue: existingStop?.expectedWeather ?? "")
        _notes = State(initialValue: existingStop?.customsNotes ?? "")
        _selectedContextRawValues = State(initialValue: Set(existingStop?.requestedContexts.map(\.rawValue) ?? []))
    }

    var body: some View {
        Form {
            Section("Day") {
                LabeledContent("Date", value: TripPlannerView.dateFormatter.string(from: date))
                TextField("Location", text: $location)
                    .textInputAutocapitalization(.words)
                TextField("Manual weather if lookup fails", text: $expectedWeather, prompt: Text("88F, sunny, wind 6 mph, humidity 70%"))
                    .textInputAutocapitalization(.sentences)
            }

            Section("Outfits Needed") {
                Text("Select only the outfit types you want generated for this date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(fitCheckPlanContextOptions) { option in
                    Toggle(option.displayName, isOn: contextBinding(for: option))
                }
            }

            Section("Notes") {
                TextField("Plans for this date", text: $notes, prompt: Text("Work day, dinner, run before work"))
                    .textInputAutocapitalization(.sentences)
            }
        }
        .navigationTitle("Daily Plan")
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
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existingStop {
            existingStop.location = trimmedLocation
            existingStop.startsAt = date
            existingStop.endsAt = date
            existingStop.expectedWeather = expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines)
            existingStop.customsNotes = notes
            existingStop.requestedContexts = selectedContexts
            existingStop.isDailyPlanEntry = true
        } else {
            let stop = TripStop(
                location: trimmedLocation,
                startsAt: date,
                endsAt: date,
                expectedWeather: expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines),
                customsNotes: notes,
                requestedContextRawValues: selectedContexts.map(\.rawValue).joined(separator: "\n"),
                isDailyPlanEntry: true,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }
        try? modelContext.save()
        dismiss()
    }

    private var selectedContexts: [OutfitContextOption] {
        fitCheckPlanContextOptions.filter { selectedContextRawValues.contains($0.rawValue) }
    }

    private func contextBinding(for option: OutfitContextOption) -> Binding<Bool> {
        Binding {
            selectedContextRawValues.contains(option.rawValue)
        } set: { isSelected in
            if isSelected {
                selectedContextRawValues.insert(option.rawValue)
            } else {
                selectedContextRawValues.remove(option.rawValue)
            }
        }
    }
}

private struct TripStopEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var trip: Trip
    private let stop: TripStop?
    @State private var location = ""
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var expectedWeather = ""
    @State private var customsNotes = ""

    init(trip: Trip, stop: TripStop? = nil) {
        self.trip = trip
        self.stop = stop
        _location = State(initialValue: stop?.location ?? "")
        _startsAt = State(initialValue: stop?.startsAt ?? trip.startsAt)
        _endsAt = State(initialValue: stop?.endsAt ?? trip.startsAt)
        _expectedWeather = State(initialValue: stop?.expectedWeather ?? "")
        _customsNotes = State(initialValue: stop?.customsNotes ?? "")
    }

    var body: some View {
        Form {
            Section("Stop") {
                TextField("Location", text: $location)
                    .textInputAutocapitalization(.words)
                DatePicker("Start", selection: $startsAt, displayedComponents: .date)
                DatePicker("End", selection: $endsAt, displayedComponents: .date)
                TextField("Manual weather if lookup fails", text: $expectedWeather, prompt: Text("88F, sunny, wind 6 mph, humidity 70%"))
                    .textInputAutocapitalization(.sentences)
            }

            Section("Notes") {
                TextField("Location notes", text: $customsNotes, prompt: Text("Hotel area, local formality, packing notes"))
                    .textInputAutocapitalization(.sentences)
                Text("Choose outfit types in Daily Plan, not here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(stop == nil ? "Add Stop" : "Edit Stop")
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
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let endDate = startsAt > endsAt ? startsAt : endsAt
        if let stop {
            stop.location = trimmedLocation
            stop.startsAt = startsAt
            stop.endsAt = endDate
            stop.expectedWeather = expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines)
            stop.customsNotes = customsNotes
            stop.requestedContexts = []
            stop.isDailyPlanEntry = false
        } else {
            let stop = TripStop(
                location: trimmedLocation,
                startsAt: startsAt,
                endsAt: endDate,
                expectedWeather: expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines),
                customsNotes: customsNotes,
                requestedContextRawValues: "",
                isDailyPlanEntry: false,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }
        try? modelContext.save()
        dismiss()
    }

}

private let fitCheckPlanContextOptions: [OutfitContextOption] = [
    .workDay,
    .travelDay,
    .casualDay,
    .walkingAroundCity,
    .dinner,
    .dateNight,
    .runningDay,
    .liftingDay,
    .gym,
    .wedding
]

private extension String {
    var fitcheckLines: [String] {
        split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
