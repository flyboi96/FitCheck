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
    @State private var location = ""
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
                TextField("Starting city", text: $location, prompt: Text("Djibouti"))
                    .textInputAutocapitalization(.words)
                DatePicker("Start", selection: $startsAt, displayedComponents: .date)
                DatePicker("End", selection: $endsAt, displayedComponents: .date)
                Text("Enter one starting city here. Add more cities later as Stops only when the location changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 96)
                Text("Optional. Add broad constraints like laundry access, dress code, work week, vacation, special events, or packing priorities.")
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
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let endDate = maxDate(startsAt, endsAt)
        let trip = Trip(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            endsAt: endDate,
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
        if !trimmedLocation.isEmpty {
            let stop = TripStop(
                location: trimmedLocation,
                startsAt: startsAt,
                endsAt: endDate,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }
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
    @State private var editingPackingItem: PackingListItem?
    @State private var dailyWeatherSummaries: [TimeInterval: String] = [:]
    @State private var isLoadingDailyWeather = false

    private let service = TripPlanningService()
    private let weatherClient = OpenMeteoWeatherClient()

    var body: some View {
        List {
            Section("Plan Summary") {
                TextField("Plan name", text: $trip.title)
                    .textInputAutocapitalization(.words)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        planMetric(title: "Stops", value: "\(sortedStops.count)", systemImage: "mappin.and.ellipse")
                        planMetric(title: "Days", value: "\(planDays.count)", systemImage: "calendar")
                    }
                    HStack(spacing: 12) {
                        planMetric(title: "Outfits", value: "\(requestedOutfitCount)", systemImage: "tshirt")
                        planMetric(title: "Generated", value: "\(trip.itineraryOutfits.count)", systemImage: "checkmark.circle")
                    }
                }
                FitCheckInlineStatus(message: planReadinessText, systemImage: planReadinessIcon)
            }

            Section("1. Stops") {
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

            Section("2. Daily Plan") {
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
                            Label(dailyWeatherText(for: day.date) ?? "Weather not loaded for this date", systemImage: "cloud.sun")
                                .font(.caption)
                                .foregroundStyle(dailyWeatherText(for: day.date) == nil ? .tertiary : .secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task {
                        await refreshDailyWeather()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isLoadingDailyWeather ? "Updating Weather" : "Update Daily Weather",
                        systemImage: "cloud.sun",
                        isLoading: isLoadingDailyWeather
                    )
                }
                .disabled(isLoadingDailyWeather || sortedStops.isEmpty)
            }

            Section("3. Laundry & Packing Rules") {
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

            Section("4. Generate") {
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
                    .frame(maxWidth: .infinity, minHeight: 44)
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
                        cacheItineraryWeather()
                        try? modelContext.save()
                        generationStatus = "Itinerary and packing list updated."
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingItinerary ? "Generating Itinerary" : itineraryButtonTitle,
                        systemImage: "calendar",
                        isLoading: isGeneratingItinerary
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
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
                Section("Packing List") {
                    ForEach(packingGroups(for: list)) { group in
                        DisclosureGroup {
                            ForEach(group.items) { packingItem in
                                PackingListRowView(
                                    packingItem: packingItem,
                                    title: packingTitle(for: packingItem),
                                    onEdit: { editingPackingItem = packingItem }
                                )
                            }
                        } label: {
                            HStack {
                                Label(group.title, systemImage: group.systemImage)
                                Spacer()
                                Text("\(group.totalQuantity)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Outfit Itinerary") {
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
        .sheet(item: $editingPackingItem) { packingItem in
            NavigationStack {
                PackingListItemEditorView(packingItem: packingItem)
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
        .onAppear {
            cacheItineraryWeather()
        }
        .onChange(of: trip.title) { _, _ in
            try? modelContext.save()
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

    private var requestedOutfitCount: Int {
        planDays.reduce(0) { total, day in
            total + requestedContexts(on: day.date).count
        }
    }

    private var planReadinessText: String {
        if sortedStops.isEmpty {
            return "Add at least one stop before generating."
        }
        if requestedOutfitCount == 0 {
            return "Daily Plan has no outfit requests yet."
        }
        return "Ready: \(requestedOutfitCount) planned outfit\(requestedOutfitCount == 1 ? "" : "s") across \(planDays.count) day\(planDays.count == 1 ? "" : "s")."
    }

    private var planReadinessIcon: String {
        sortedStops.isEmpty || requestedOutfitCount == 0 ? "info.circle" : "checkmark.circle"
    }

    private func planMetric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline.monospacedDigit())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
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
        feedbackStatus = "Feedback saved. Similar itinerary outfits will be adjusted next time."
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

    private func dailyWeatherText(for date: Date) -> String? {
        let key = dayKey(for: date)
        if let cached = dailyWeatherSummaries[key] {
            return cached
        }

        return trip.itineraryOutfits
            .first { Calendar.current.isDate($0.date, inSameDayAs: date) }?
            .outfit?
            .weatherSummary
    }

    private func cacheItineraryWeather() {
        var updated = dailyWeatherSummaries
        for itinerary in trip.itineraryOutfits {
            if let summary = itinerary.outfit?.weatherSummary,
               !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated[dayKey(for: itinerary.date)] = summary
            }
        }
        dailyWeatherSummaries = updated
    }

    @MainActor
    private func refreshDailyWeather() async {
        guard !isLoadingDailyWeather else { return }
        isLoadingDailyWeather = true
        generationStatus = "Updating weather for each plan day."
        defer {
            isLoadingDailyWeather = false
        }

        var updated = dailyWeatherSummaries
        var updatedCount = 0

        for day in planDays {
            let location = primaryLocation(for: day.date)
            guard !location.isEmpty else { continue }

            if let result = try? await weatherClient.dailyWeather(for: location, date: day.date) {
                updated[dayKey(for: day.date)] = weatherSummaryText(for: result)
                updatedCount += 1
            }
        }

        dailyWeatherSummaries = updated
        generationStatus = updatedCount == 0
            ? "Daily weather lookup did not return results. Manual weather can still be set per day."
            : "Updated weather for \(updatedCount) day\(updatedCount == 1 ? "" : "s")."
    }

    private func primaryLocation(for date: Date) -> String {
        if let dailyPlanLocation = dailyPlanStop(on: date)?.location.trimmingCharacters(in: .whitespacesAndNewlines),
           !dailyPlanLocation.isEmpty {
            return dailyPlanLocation
        }

        return locationStops(on: date)
            .last?
            .location
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func weatherSummaryText(for result: WeatherLookupResult) -> String {
        [
            "\(Int(result.input.temperatureF.rounded()))F",
            result.condition,
            "wind \(Int(result.input.windMph.rounded())) mph",
            result.input.humidityPercent.map { "humidity \(Int($0.rounded()))%" }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func dayKey(for date: Date) -> TimeInterval {
        Calendar.current.startOfDay(for: date).timeIntervalSinceReferenceDate
    }

    private func packingTitle(for item: PackingListItem) -> String {
        if let clothingName = item.item?.name {
            return clothingName
        }
        return item.reason.isEmpty ? "Packing item" : item.reason
    }

    private func packingGroups(for list: PackingList) -> [PackingListGroup] {
        let grouped = Dictionary(grouping: list.items) { packingGroupTitle(for: $0) }
        return grouped
            .map { title, items in
                PackingListGroup(
                    title: title,
                    systemImage: packingGroupSystemImage(for: title),
                    items: items.sorted(by: packingItemSort),
                    sortIndex: packingGroupSortIndex(title)
                )
            }
            .sorted {
                if $0.sortIndex == $1.sortIndex {
                    return $0.title < $1.title
                }
                return $0.sortIndex < $1.sortIndex
            }
    }

    private func packingGroupTitle(for packingItem: PackingListItem) -> String {
        if packingItem.item == nil {
            return "Needs"
        }

        switch packingItem.item?.category {
        case .shirt, .blouse, .sweater, .dress:
            return "Tops"
        case .pants, .shorts, .skirt:
            return "Bottoms"
        case .underwear, .socks:
            return "Underwear & Socks"
        case .shoes, .heels, .flats:
            return "Shoes"
        case .jacket:
            return "Outerwear"
        case .activewear:
            let reason = packingItem.reason.lowercased()
            if reason.contains("underwear") || reason.contains("socks") {
                return "Underwear & Socks"
            }
            return "Exercise"
        case .belt, .watch, .jewelry, .accessory, .bag, .purse:
            return "Accessories"
        case .other, nil:
            return "Other"
        }
    }

    private func packingGroupSystemImage(for title: String) -> String {
        switch title {
        case "Tops":
            return "tshirt"
        case "Bottoms":
            return "figure.stand"
        case "Underwear & Socks":
            return "shoeprints.fill"
        case "Shoes":
            return "shoeprints.fill"
        case "Outerwear":
            return "cloud"
        case "Exercise":
            return "figure.run"
        case "Accessories":
            return "sparkles"
        case "Needs":
            return "exclamationmark.triangle"
        default:
            return "list.bullet"
        }
    }

    private func packingGroupSortIndex(_ title: String) -> Int {
        ["Needs", "Tops", "Bottoms", "Underwear & Socks", "Shoes", "Outerwear", "Exercise", "Accessories", "Other"]
            .firstIndex(of: title) ?? 99
    }

    private func packingItemSort(_ first: PackingListItem, _ second: PackingListItem) -> Bool {
        let firstTitle = packingTitle(for: first)
        let secondTitle = packingTitle(for: second)
        if first.item?.category == second.item?.category {
            return firstTitle.localizedCaseInsensitiveCompare(secondTitle) == .orderedAscending
        }
        return categorySortIndex(first.item?.category) < categorySortIndex(second.item?.category)
    }

    private func categorySortIndex(_ category: ClothingCategory?) -> Int {
        guard let category else { return -1 }
        return ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
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
            for group in packingGroups(for: list) {
                lines.append(group.title)
                for packingItem in group.items {
                    lines.append("- \(packingTitle(for: packingItem)) x\(packingItem.quantity)")
                    if packingItem.item != nil, !packingItem.reason.isEmpty {
                        lines.append("  \(packingItem.reason)")
                    }
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

private struct PackingListGroup: Identifiable {
    var title: String
    var systemImage: String
    var items: [PackingListItem]
    var sortIndex: Int

    var id: String { title }

    var totalQuantity: Int {
        items.reduce(0) { $0 + max(1, $1.quantity) }
    }
}

private struct PackingListRowView: View {
    var packingItem: PackingListItem
    var title: String
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: packingItem.item?.category.systemImageName ?? "exclamationmark.triangle")
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text("x\(packingItem.quantity)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                if let item = packingItem.item {
                    Text([item.category.displayName, item.brand.isEmpty ? nil : item.brand].compactMap { $0 }.joined(separator: " - "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !packingItem.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(packingItem.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(action: onEdit) {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Edit \(title)")
        }
        .padding(.vertical, 4)
    }
}

private struct PackingListItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]

    @Bindable var packingItem: PackingListItem
    @State private var searchText = ""
    @State private var selectedCategoryRawValue = "current"
    @State private var status = ""

    var body: some View {
        Form {
            Section("Current Packing Item") {
                if let item = packingItem.item {
                    LabeledContent("Item", value: item.name)
                    LabeledContent("Category", value: item.category.displayName)
                } else {
                    TextField("Manual item", text: $packingItem.reason)
                        .textInputAutocapitalization(.sentences)
                }

                Stepper(value: $packingItem.quantity, in: 1...99) {
                    LabeledContent("Quantity", value: "\(packingItem.quantity)")
                }

                if packingItem.item != nil {
                    TextField("Packing note", text: $packingItem.reason)
                        .textInputAutocapitalization(.sentences)
                }
            }

            Section("Swap From Closet") {
                Picker("Category", selection: $selectedCategoryRawValue) {
                    Text("Same Category").tag("current")
                    Text("All Categories").tag("all")
                    ForEach(availableCategories) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                .pickerStyle(.menu)

                TextField("Search closet", text: $searchText)
                    .textInputAutocapitalization(.words)

                ForEach(Array(replacementItems.prefix(40))) { item in
                    Button {
                        replace(with: item)
                    } label: {
                        HStack {
                            Label(item.name, systemImage: item.category.systemImageName)
                            Spacer()
                            Text(item.quantity > 1 ? "Qty \(item.quantity)" : item.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    deletePackingItem()
                } label: {
                    Label("Remove From Packing List", systemImage: "trash")
                }

                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Edit Packing")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    saveAndDismiss()
                }
            }
        }
        .onChange(of: packingItem.quantity) { _, _ in
            try? modelContext.save()
        }
        .onChange(of: packingItem.reason) { _, _ in
            try? modelContext.save()
        }
    }

    private var availableCategories: [ClothingCategory] {
        let categories = Set(closetItems.filter { $0.status == .active }.map(\.category))
        return ClothingCategory.allCases.filter { categories.contains($0) }
    }

    private var replacementItems: [ClothingItem] {
        let activeItems = closetItems.filter { $0.status == .active && $0.id != packingItem.item?.id }
        let categoryFiltered = activeItems.filter { item in
            switch selectedCategoryRawValue {
            case "current":
                guard let currentCategory = packingItem.item?.category else { return true }
                return item.category == currentCategory
            case "all":
                return true
            default:
                return item.category.rawValue == selectedCategoryRawValue
            }
        }
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return categoryFiltered
            .filter { search.isEmpty || searchableText(for: $0).localizedCaseInsensitiveContains(search) }
            .sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return categorySortIndex($0.category) < categorySortIndex($1.category)
            }
    }

    private func replace(with item: ClothingItem) {
        packingItem.item = item
        if packingItem.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            packingItem.reason.localizedCaseInsensitiveContains("Add ") {
            packingItem.reason = "Manual packing swap"
        }
        try? modelContext.save()
        status = "Now packing \(item.name)."
    }

    private func deletePackingItem() {
        packingItem.packingList?.items.removeAll { $0.id == packingItem.id }
        modelContext.delete(packingItem)
        try? modelContext.save()
        dismiss()
    }

    private func saveAndDismiss() {
        packingItem.quantity = max(1, packingItem.quantity)
        try? modelContext.save()
        dismiss()
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

    private func categorySortIndex(_ category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
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
    @State private var applyToEmptyDays = false

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

            Section("Apply") {
                Toggle("Copy to empty days", isOn: $applyToEmptyDays)
                Text("Copies this location, manual weather, notes, and outfit requests only to dates that do not already have a Daily Plan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        let trimmedWeather = expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines)
        let contexts = selectedContexts
        if let existingStop {
            existingStop.location = trimmedLocation
            existingStop.startsAt = date
            existingStop.endsAt = date
            existingStop.expectedWeather = trimmedWeather
            existingStop.customsNotes = notes
            existingStop.requestedContexts = contexts
            existingStop.isDailyPlanEntry = true
        } else {
            let stop = TripStop(
                location: trimmedLocation,
                startsAt: date,
                endsAt: date,
                expectedWeather: trimmedWeather,
                customsNotes: notes,
                requestedContextRawValues: contexts.map(\.rawValue).joined(separator: "\n"),
                isDailyPlanEntry: true,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }

        if applyToEmptyDays {
            copyPlanToEmptyDays(
                location: trimmedLocation,
                weather: trimmedWeather,
                notes: notes,
                contexts: contexts
            )
        }

        try? modelContext.save()
        dismiss()
    }

    private func copyPlanToEmptyDays(
        location: String,
        weather: String,
        notes: String,
        contexts: [OutfitContextOption]
    ) {
        for day in dates(from: trip.startsAt, through: trip.endsAt) {
            guard !Calendar.current.isDate(day, inSameDayAs: date), dailyPlanStop(on: day) == nil else {
                continue
            }

            let stop = TripStop(
                location: location,
                startsAt: day,
                endsAt: day,
                expectedWeather: weather,
                customsNotes: notes,
                requestedContextRawValues: contexts.map(\.rawValue).joined(separator: "\n"),
                isDailyPlanEntry: true,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }
    }

    private func dailyPlanStop(on date: Date) -> TripStop? {
        let startOfDay = Calendar.current.startOfDay(for: date)
        return trip.stops.first { stop in
            Calendar.current.startOfDay(for: stop.startsAt) == startOfDay &&
                Calendar.current.startOfDay(for: stop.endsAt) == startOfDay &&
                stop.isDailyPlanEntry
        }
    }

    private func dates(from start: Date, through end: Date) -> [Date] {
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        let dayCount = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        guard dayCount >= 0 else { return [startDay] }
        return (0...dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: startDay) }
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
