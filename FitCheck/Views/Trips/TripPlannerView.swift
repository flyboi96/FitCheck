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

    private let service = TripPlanningService()

    var body: some View {
        List {
            Section("Stops") {
                Text("Stops can be cities for travel or your home city for a regular week.")
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

                Text("Packing uses these values to reduce overpacking. Underwear and socks are still recommended as one per day, plus extras for exercise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Generate") {
                Button {
                    Task { @MainActor in
                        isGeneratingPackingList = true
                        generationStatus = "Generating packing list from your closet and trip stops."
                        await service.rebuildPackingList(for: trip, closet: closetItems, context: modelContext)
                        try? modelContext.save()
                        generationStatus = "Packing list updated with \(trip.packingLists.flatMap(\.items).count) item rows."
                        isGeneratingPackingList = false
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
                        try? modelContext.save()
                        generationStatus = "Itinerary updated with \(trip.itineraryOutfits.count) daily outfit\(trip.itineraryOutfits.count == 1 ? "" : "s")."
                        isGeneratingItinerary = false
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingItinerary ? "Generating Itinerary" : itineraryButtonTitle,
                        systemImage: "calendar",
                        isLoading: isGeneratingItinerary
                    )
                }
                .disabled(isGeneratingItinerary || trip.stops.isEmpty)

                FitCheckInlineStatus(
                    message: generationStatus,
                    isLoading: isGeneratingPackingList || isGeneratingItinerary
                )

                Text("For a normal week, add one stop for your city across the whole date range, then generate an itinerary.")
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
        trip.stops.sorted { $0.startsAt < $1.startsAt }
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

        if !trip.stops.isEmpty {
            lines.append("Stops")
            for stop in trip.stops.sorted(by: { $0.startsAt < $1.startsAt }) {
                lines.append("- \(stop.location): \(TripPlannerView.dateFormatter.string(from: stop.startsAt)) - \(TripPlannerView.dateFormatter.string(from: stop.endsAt))")
                if !stop.expectedWeather.isEmpty {
                    lines.append("  Weather: \(stop.expectedWeather)")
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
                        ForEach(outfit.notes.fitcheckLines, id: \.self) { note in
                            Label(note, systemImage: "checkmark.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
            TextField("Location", text: $location)
                .textInputAutocapitalization(.words)
            DatePicker("Start", selection: $startsAt, displayedComponents: .date)
            DatePicker("End", selection: $endsAt, displayedComponents: .date)
            TextField("Manual weather if lookup fails", text: $expectedWeather, prompt: Text("88F, sunny, wind 6 mph, humidity 70%"))
                .textInputAutocapitalization(.sentences)
            TextField("Daily plans", text: $customsNotes, prompt: Text("Work days, dinner nights, gym 3x, casual sightseeing"))
                .textInputAutocapitalization(.sentences)
            Text("Use separate stops for date-specific plans, or describe multiple contexts here. FitCheck can create more than one outfit for a day.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        } else {
            let stop = TripStop(
                location: trimmedLocation,
                startsAt: startsAt,
                endsAt: endDate,
                expectedWeather: expectedWeather.trimmingCharacters(in: .whitespacesAndNewlines),
                customsNotes: customsNotes,
                trip: trip
            )
            modelContext.insert(stop)
            trip.stops.append(stop)
        }
        try? modelContext.save()
        dismiss()
    }
}

private extension String {
    var fitcheckLines: [String] {
        split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
