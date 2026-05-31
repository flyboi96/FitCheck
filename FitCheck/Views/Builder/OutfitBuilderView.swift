import SwiftData
import SwiftUI

struct OutfitBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]
    @Query(sort: \Feedback.createdAt, order: .reverse) private var feedback: [Feedback]
    @Query private var stylePreferences: [StylePreference]
    @Query(sort: \UserAvatar.updatedAt, order: .reverse) private var avatars: [UserAvatar]

    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var manualLocationQuery = ""
    @State private var manualWeatherLocation = ""
    @State private var manualWeatherTemperature = "72"
    @State private var manualWeatherWind = "5"
    @State private var manualWeatherHumidity = ""
    @State private var manualWeatherCondition = "Clear"
    @State private var manualWeatherIsRaining = false
    @State private var manualWeatherOverride: WeatherInput?
    @State private var selectedItemID: UUID?
    @State private var itemSearchText = ""
    @State private var selectedCategoryRawValue = "all"
    @State private var selectedContext = OutfitContextOption.casualDay.rawValue
    @State private var recommendations: [OutfitRecommendation] = []
    @State private var aiReviews: [String: AIOutfitResponse] = [:]
    @State private var aiReviewErrors: [String: String] = [:]
    @State private var reviewingCombinationKeys = Set<String>()
    @State private var avatarPreviews: [String: Data] = [:]
    @State private var avatarPreviewErrors: [String: String] = [:]
    @State private var avatarPreviewingCombinationKeys = Set<String>()
    @State private var isGeneratingLocal = false
    @State private var isAIChoosingOutfit = false
    @State private var aiBuildError = ""
    @State private var weatherActionStatus = ""
    @State private var builderStatus = ""
    @State private var noMatchReasons: [String] = []
    @State private var feedbackTarget: OutfitRecommendation?
    @State private var editingRecommendation: OutfitRecommendation?

    private let engine = OutfitRecommendationEngine()

    var body: some View {
        List {
            Section("Anchor Item") {
                if let selectedItem {
                    HStack {
                        Label(selectedItem.name, systemImage: iconName(for: selectedItem.category))
                        Spacer()
                        Text(selectedItem.category.displayName)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Label("Choose one closet item to build around", systemImage: "tshirt")
                        .foregroundStyle(.secondary)
                }

                TextField("Search closet", text: $itemSearchText)
                    .textInputAutocapitalization(.words)

                Picker("Category", selection: $selectedCategoryRawValue) {
                    Text("All Categories").tag("all")
                    ForEach(availableCategories) { category in
                        Text(category.displayName).tag(category.rawValue)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Weather") {
                weatherStatus
                TextField("City or place", text: $manualLocationQuery)
                    .textInputAutocapitalization(.words)
                Button {
                    refreshWeather()
                } label: {
                    FitCheckButtonLabel(
                        title: weatherLookup.isLoading ? "Looking Up Weather" : "Use Current Location",
                        systemImage: "location",
                        isLoading: weatherLookup.isLoading
                    )
                }
                .disabled(weatherLookup.isLoading)

                Button {
                    lookupManualWeather()
                } label: {
                    FitCheckButtonLabel(
                        title: weatherLookup.isLoading ? "Looking Up Location" : "Look Up Location",
                        systemImage: "magnifyingglass",
                        isLoading: weatherLookup.isLoading
                    )
                }
                .disabled(weatherLookup.isLoading || manualLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                manualWeatherControls
                FitCheckInlineStatus(
                    message: weatherLookup.isLoading ? weatherLoadingMessage : weatherActionStatus,
                    isLoading: weatherLookup.isLoading
                )
            }

            Section("Context") {
                Picker("Context", selection: $selectedContext) {
                    ForEach(OutfitContextOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Button {
                    generateWithVisibleFeedback()
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingLocal ? "Building Outfit" : "Build Outfit",
                        systemImage: "wand.and.stars",
                        isLoading: isGeneratingLocal
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedItem == nil || effectiveWeather == nil || isGeneratingLocal)

                Button {
                    Task {
                        await generateWithAIFirst()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isAIChoosingOutfit ? "Asking AI" : "Ask AI First",
                        systemImage: "sparkles",
                        isLoading: isAIChoosingOutfit
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(!canAskAIForOutfit)

                Text("Build Outfit uses the local scoring engine. Ask AI First lets the proxy choose from your closet, then FitCheck scores that outfit locally and shows the AI rationale.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !aiBuildError.isEmpty {
                    Text(aiBuildError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                FitCheckInlineStatus(message: builderStatus)
                FitCheckNoMatchDiagnosticsView(reasons: noMatchReasons)
            }

            if filteredItemGroups.isEmpty {
                Section("Pick Item") {
                    ContentUnavailableView("No Matching Items", systemImage: "magnifyingglass")
                }
            } else {
                BuilderItemSelectionList(
                    groups: filteredItemGroups,
                    selectedItemID: $selectedItemID
                )
            }

            if !recommendations.isEmpty {
                Section("Outfits") {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(
                            recommendation: recommendation,
                            onFeedback: { feedbackTarget = recommendation },
                            onEdit: { editingRecommendation = recommendation },
                            aiReview: aiReviews[recommendation.combinationKey],
                            aiReviewError: aiReviewErrors[recommendation.combinationKey],
                            isAIReviewing: reviewingCombinationKeys.contains(recommendation.combinationKey),
                            onAIReview: aiReviewAction(for: recommendation),
                            avatarPreviewData: avatarPreviews[recommendation.combinationKey],
                            avatarPreviewError: avatarPreviewErrors[recommendation.combinationKey],
                            isGeneratingAvatarPreview: avatarPreviewingCombinationKeys.contains(recommendation.combinationKey),
                            onAvatarPreview: avatarPreviewAction(for: recommendation)
                        )
                    }
                }
            }
        }
        .navigationTitle("Build")
        .task {
            if weatherLookup.result == nil {
                refreshWeather()
            }
        }
        .onChange(of: weatherLookup.isLoading) { _, isLoading in
            updateWeatherActionStatus(isLoading: isLoading)
        }
        .sheet(item: $feedbackTarget) { recommendation in
            OutfitFeedbackEditorView(title: "Builder Feedback") { type, note in
                recordFeedback(for: recommendation, type: type, note: note)
            }
        }
        .sheet(item: $editingRecommendation) { recommendation in
            if let request = currentRecommendationRequest {
                RecommendationDraftEditorView(
                    recommendation: recommendation,
                    closetItems: activeItems,
                    feedback: feedback,
                    stylePreference: stylePreferences.first,
                    request: request
                ) { updated in
                    saveEditedRecommendation(updated)
                }
            } else {
                ContentUnavailableView("Weather Needed", systemImage: "cloud.sun", description: Text("Load weather before editing and rescoring this outfit."))
            }
        }
    }

    private var activeItems: [ClothingItem] {
        closetItems
            .filter { $0.status == .active }
            .sorted {
                if $0.category == $1.category {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return categorySortIndex($0.category) < categorySortIndex($1.category)
            }
    }

    private var selectedItem: ClothingItem? {
        guard let selectedItemID else { return nil }
        return activeItems.first { $0.id == selectedItemID }
    }

    private var availableCategories: [ClothingCategory] {
        let categories = Set(activeItems.map(\.category))
        return ClothingCategory.allCases.filter { categories.contains($0) }
    }

    private var filteredItemGroups: [ItemCategoryGroup] {
        let search = itemSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = activeItems.filter { item in
            let matchesCategory = selectedCategoryRawValue == "all" || item.category.rawValue == selectedCategoryRawValue
            let matchesSearch = search.isEmpty || item.name.localizedCaseInsensitiveContains(search)
            return matchesCategory && matchesSearch
        }

        return availableCategories.compactMap { category in
            let items = filtered.filter { $0.category == category }
            guard !items.isEmpty else { return nil }
            return ItemCategoryGroup(category: category, items: items)
        }
    }

    @ViewBuilder
    private var weatherStatus: some View {
        if let manualWeatherOverride {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(manualWeatherOverride.temperatureF.rounded()))F · \(manualWeatherCondition)")
                    .font(.body.weight(.medium))
                Text("\(manualWeatherOverride.location) · Wind \(Int(manualWeatherOverride.windMph.rounded())) mph\(humidityStatusText(for: manualWeatherOverride)) · Manual weather")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if weatherLookup.isLoading {
            Label("Looking up weather", systemImage: "cloud.sun")
                .foregroundStyle(.secondary)
        } else if let result = weatherLookup.result {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(result.input.temperatureF.rounded()))F · \(result.condition)")
                    .font(.body.weight(.medium))
                Text("\(result.input.location) · Wind \(Int(result.input.windMph.rounded())) mph\(humidityStatusText(for: result.input))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Label("Weather not loaded", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        }

        if let message = weatherLookup.errorMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var manualWeatherControls: some View {
        DisclosureGroup("Manual Weather") {
            TextField("City or place", text: $manualWeatherLocation)
                .textInputAutocapitalization(.words)
            TextField("Temperature F", text: $manualWeatherTemperature)
                .keyboardType(.numbersAndPunctuation)
            TextField("Condition", text: $manualWeatherCondition)
                .textInputAutocapitalization(.words)
            Toggle("Raining", isOn: $manualWeatherIsRaining)
            TextField("Wind mph", text: $manualWeatherWind)
                .keyboardType(.numbersAndPunctuation)
            TextField("Humidity %", text: $manualWeatherHumidity)
                .keyboardType(.numbersAndPunctuation)

            HStack {
                Button {
                    applyManualWeather()
                } label: {
                    Label("Use Manual Weather", systemImage: "thermometer.sun")
                }
                .disabled(manualWeatherInput == nil)

                if manualWeatherOverride != nil {
                    Button("Clear") {
                        manualWeatherOverride = nil
                    }
                }
            }
        }
    }

    private func refreshWeather() {
        weatherActionStatus = "Looking up weather from current location or default city."
        weatherLookup.refresh(defaultLocationName: fallbackName)
    }

    private func lookupManualWeather() {
        let query = manualLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        weatherActionStatus = "Looking up weather for \(query)."
        weatherLookup.refresh(searchText: manualLocationQuery)
    }

    private func generate() {
        guard let selectedItem, let weather = effectiveWeather else { return }
        aiReviews = [:]
        aiReviewErrors = [:]
        avatarPreviews = [:]
        avatarPreviewErrors = [:]
        aiBuildError = ""
        let request = RecommendationRequest(
            weather: weather,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            selectedItem: selectedItem
        )
        recommendations = engine.recommend(
            closet: closetItems,
            feedback: feedback,
            stylePreference: stylePreferences.first,
            request: request
        )
        if recommendations.isEmpty {
            noMatchReasons = engine.noMatchReasons(
                closet: closetItems,
                stylePreference: stylePreferences.first,
                request: request
            )
            builderStatus = "No outfit matched. See blockers below."
        } else {
            noMatchReasons = []
            builderStatus = "Built \(recommendations.count) outfit\(recommendations.count == 1 ? "" : "s") around \(selectedItem.name)."
        }
    }

    private func generateWithVisibleFeedback() {
        guard !isGeneratingLocal else { return }
        isGeneratingLocal = true
        builderStatus = "Building outfit with local scoring."

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            generate()
            isGeneratingLocal = false
        }
    }

    private var canAskAIForOutfit: Bool {
        useAIProxy &&
        configuredAIProxyURL != nil &&
        effectiveWeather != nil &&
        !isAIChoosingOutfit &&
        activeItems.count >= 3
    }

    @MainActor
    private func generateWithAIFirst() async {
        guard let baseURL = configuredAIProxyURL, let weather = effectiveWeather else { return }

        isAIChoosingOutfit = true
        aiBuildError = ""
        builderStatus = "Asking AI to build around your selected item."
        noMatchReasons = []
        aiReviews = [:]
        aiReviewErrors = [:]
        avatarPreviews = [:]
        avatarPreviewErrors = [:]
        defer {
            isAIChoosingOutfit = false
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.suggestOutfit(
                request: aiRequest(
                    candidateItemIDs: [],
                    localScore: nil,
                    localNotes: []
                )
            )
            let itemsByID = Dictionary(uniqueKeysWithValues: closetItems.map { ($0.id, $0) })
            var chosenItems = response.itemIDs.compactMap { itemsByID[$0] }

            if let selectedItem, !chosenItems.contains(where: { $0.id == selectedItem.id }) {
                chosenItems.insert(selectedItem, at: 0)
            }

            let request = RecommendationRequest(
                weather: weather,
                occasion: currentContext.occasion,
                activity: currentContext.activity,
                selectedItem: selectedItem
            )

            guard engine.isCompleteOutfit(chosenItems, request: request) else {
                aiBuildError = "AI returned an incomplete outfit. Try Ask AI First again or use Build Outfit."
                builderStatus = "AI returned an incomplete outfit."
                noMatchReasons = engine.noMatchReasons(
                    closet: closetItems,
                    stylePreference: stylePreferences.first,
                    request: request
                )
                return
            }

            let recommendation = engine.scoreExistingOutfit(
                items: chosenItems,
                feedback: feedback,
                stylePreference: stylePreferences.first,
                request: request,
                title: "AI Fit"
            )

            recommendations = [recommendation]
            aiReviews[recommendation.combinationKey] = response
            noMatchReasons = []
            builderStatus = "AI picked an outfit and FitCheck scored it locally."
        } catch {
            aiBuildError = error.localizedDescription
            builderStatus = "AI outfit request failed."
        }
    }

    private func aiReviewAction(for recommendation: OutfitRecommendation) -> (() -> Void)? {
        guard useAIProxy, configuredAIProxyURL != nil else { return nil }
        return {
            Task {
                await reviewWithAI(recommendation)
            }
        }
    }

    private func recordFeedback(for recommendation: OutfitRecommendation, type: FeedbackType, note: String) {
        let entry = Feedback(type: type, note: note, combinationKey: recommendation.combinationKey)
        modelContext.insert(entry)
        try? modelContext.save()
        builderStatus = "Feedback saved. Similar builder outfits will be adjusted next time."
        generate()
    }

    private func saveEditedRecommendation(_ updated: OutfitRecommendation) {
        if let index = recommendations.firstIndex(where: { $0.id == updated.id }) {
            recommendations[index] = updated
        }
        aiReviews = [:]
        aiReviewErrors = [:]
        avatarPreviews = [:]
        avatarPreviewErrors = [:]
        noMatchReasons = []
        builderStatus = "Edited outfit and updated the score."
    }

    private func avatarPreviewAction(for recommendation: OutfitRecommendation) -> (() -> Void)? {
        let key = recommendation.combinationKey
        if let avatar = avatars.first,
           avatar.latestPreviewCombinationKey == key,
           let previewData = avatar.latestPreviewData {
            return {
                avatarPreviews[key] = previewData
                builderStatus = "Reused saved avatar preview."
            }
        }

        guard useAIProxy, configuredAIProxyURL != nil, avatarReferencePhoto != nil else { return nil }
        return {
            Task {
                await generateAvatarPreview(for: recommendation)
            }
        }
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var avatarReferencePhoto: (data: Data, mimeType: String)? {
        guard let data = avatars.first?.avatarImageData ?? avatars.first?.sourcePhotoData else { return nil }
        return (data, data.fitcheckImageMimeType)
    }

    @MainActor
    private func reviewWithAI(_ recommendation: OutfitRecommendation) async {
        guard let baseURL = configuredAIProxyURL else { return }

        let key = recommendation.combinationKey
        reviewingCombinationKeys.insert(key)
        aiReviewErrors[key] = nil
        defer {
            reviewingCombinationKeys.remove(key)
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.suggestOutfit(request: aiRequest(for: recommendation))
            aiReviews[key] = response
        } catch {
            aiReviewErrors[key] = error.localizedDescription
        }
    }

    @MainActor
    private func generateAvatarPreview(for recommendation: OutfitRecommendation) async {
        guard
            let baseURL = configuredAIProxyURL,
            let referencePhoto = avatarReferencePhoto,
            let weather = effectiveWeather
        else {
            return
        }

        let key = recommendation.combinationKey
        avatarPreviewingCombinationKeys.insert(key)
        avatarPreviewErrors[key] = nil
        defer {
            avatarPreviewingCombinationKeys.remove(key)
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.generateAvatarPreview(
                request: AIAvatarPreviewRequest(
                    userImageBase64: referencePhoto.data.base64EncodedString(),
                    mimeType: referencePhoto.mimeType,
                    outfitItems: recommendation.items.map(AIClothingItemPayload.init),
                    weatherSummary: weather.summary,
                    location: weather.location,
                    backgroundContext: avatarBackgroundContext(for: weather, condition: currentWeatherCondition),
                    wearerProfile: currentWearerProfile.displayName,
                    styleDescription: styleDescription,
                    avatarNotes: avatars.first?.notes ?? "",
                    weatherCondition: currentWeatherCondition,
                    temperatureF: weather.temperatureF,
                    isRaining: weather.isRaining,
                    windMph: weather.windMph,
                    humidityPercent: weather.humidityPercent,
                    usesSavedAvatar: avatars.first?.avatarImageData != nil
                )
            )

            guard let imageData = Data(base64Encoded: response.imageBase64) else {
                avatarPreviewErrors[key] = "The avatar preview could not be decoded."
                return
            }

            avatarPreviews[key] = imageData
            if let avatar = avatars.first {
                avatar.latestPreviewData = imageData
                avatar.latestPreviewCombinationKey = key
                avatar.updatedAt = Date()
                try? modelContext.save()
            }
        } catch {
            avatarPreviewErrors[key] = error.localizedDescription
        }
    }

    private func aiRequest(for recommendation: OutfitRecommendation) -> AIOutfitRequest {
        aiRequest(
            candidateItemIDs: recommendation.items.map(\.id),
            localScore: recommendation.score,
            localNotes: recommendation.notes
        )
    }

    private func aiRequest(
        candidateItemIDs: [UUID],
        localScore: Double?,
        localNotes: [String]
    ) -> AIOutfitRequest {
        AIOutfitRequest(
            closet: closetItems.map(AIClothingItemPayload.init),
            weatherSummary: effectiveWeather?.summary ?? "",
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            styleDescription: styleDescription,
            selectedItemID: selectedItem?.id,
            candidateItemIDs: candidateItemIDs,
            localScore: localScore,
            localNotes: localNotes,
            recentFeedback: feedback.prefix(12).map(feedbackSummary)
        )
    }

    private var styleDescription: String {
        let wearerLine = currentWearerProfile == .unspecified ? nil : "Wearer profile: \(currentWearerProfile.displayName)"
        guard let stylePreference = stylePreferences.first else { return wearerLine ?? "" }
        return [
            wearerLine,
            stylePreference.styleDescription,
            stylePreference.favoriteLooks,
            stylePreference.preferredColors,
            stylePreference.preferredFit,
            "Temperature comfort: \(stylePreference.temperatureSensitivity.displayName)",
            stylePreference.statementPiecePreference.isEmpty ? nil : "Statement pieces: \(stylePreference.statementPiecePreference)",
            stylePreference.rules,
            stylePreference.dislikedCombinations.isEmpty ? nil : "Avoid: \(stylePreference.dislikedCombinations)"
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

    private var currentContext: OutfitContextOption {
        OutfitContextOption(rawValue: selectedContext) ?? .casualDay
    }

    private var currentRecommendationRequest: RecommendationRequest? {
        guard let weather = effectiveWeather else { return nil }
        return RecommendationRequest(
            weather: weather,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            selectedItem: selectedItem
        )
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private var currentWeatherCondition: String {
        manualWeatherOverride == nil ? weatherLookup.result?.condition ?? "" : manualWeatherCondition
    }

    private var effectiveWeather: WeatherInput? {
        manualWeatherOverride ?? weatherLookup.result?.input
    }

    private var manualWeatherInput: WeatherInput? {
        guard let temperature = Double(manualWeatherTemperature.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let wind = Double(manualWeatherWind.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let humidity = Double(manualWeatherHumidity.trimmingCharacters(in: .whitespacesAndNewlines))
            .map { min(100, max(0, $0)) }
        let location = manualWeatherLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        return WeatherInput(
            temperatureF: temperature,
            isRaining: manualWeatherIsRaining,
            windMph: wind,
            location: location.isEmpty ? "Manual location" : location,
            humidityPercent: humidity
        )
    }

    private func applyManualWeather() {
        guard let manualWeatherInput else { return }
        manualWeatherOverride = manualWeatherInput
        weatherActionStatus = "Manual weather applied for \(manualWeatherInput.location)."
    }

    private var weatherLoadingMessage: String {
        weatherActionStatus.isEmpty ? "Looking up weather." : weatherActionStatus
    }

    private func updateWeatherActionStatus(isLoading: Bool) {
        guard !isLoading else { return }
        if let result = weatherLookup.result {
            weatherActionStatus = "Weather ready for \(result.input.location)."
        } else if let message = weatherLookup.errorMessage {
            weatherActionStatus = message
        }
    }

    private func humidityStatusText(for weather: WeatherInput) -> String {
        guard let humidity = weather.humidityPercent else { return "" }
        return " · Humidity \(Int(humidity.rounded()))%"
    }

    private func avatarBackgroundContext(for weather: WeatherInput, condition: String) -> String {
        let conditionText = condition.trimmingCharacters(in: .whitespacesAndNewlines)
        let rainRule = weather.isRaining
            ? "Show the real wet-weather conditions, but keep the outfit readable."
            : "Do not show rain, wet pavement, umbrellas, mist, storm clouds, or heavy overcast."
        let temperatureRule: String
        if weather.temperatureF >= 90 {
            temperatureRule = "Make it visibly hot, bright, dry, and sunlit."
        } else if weather.temperatureF >= 80 {
            temperatureRule = "Make it warm and sunlit unless the condition says otherwise."
        } else if weather.temperatureF <= 45 {
            temperatureRule = "Make it cool or cold without hiding the outfit."
        } else {
            temperatureRule = "Use mild-weather visual cues."
        }

        return [
            "Use a location-specific background for \(weather.location), not a generic cloudy city.",
            "\(Int(weather.temperatureF.rounded()))F\(conditionText.isEmpty ? "" : ", \(conditionText)").",
            "Wind \(Int(weather.windMph.rounded())) mph.",
            weather.humidityPercent.map { "Humidity \(Int($0.rounded()))%." },
            rainRule,
            temperatureRule,
            "For hot, dry places such as Djibouti, use bright arid/coastal light and avoid Seattle-like rain or gray skies unless rain is explicitly reported."
        ].compactMap { $0 }.joined(separator: " ")
    }

    private func iconName(for category: ClothingCategory) -> String {
        category.systemImageName
    }

    private func categorySortIndex(_ category: ClothingCategory) -> Int {
        ClothingCategory.allCases.firstIndex(of: category) ?? ClothingCategory.allCases.count
    }
}

private struct ItemCategoryGroup: Identifiable {
    var category: ClothingCategory
    var items: [ClothingItem]

    var id: String { category.rawValue }
}

private struct BuilderItemSelectionList: View {
    var groups: [ItemCategoryGroup]
    @Binding var selectedItemID: UUID?

    var body: some View {
        ForEach(groups) { group in
            Section(group.category.displayName) {
                ForEach(group.items) { item in
                    Button {
                        selectedItemID = item.id
                    } label: {
                        BuilderClosetItemRow(
                            name: item.name,
                            imageName: item.category.systemImageName,
                            detail: Self.itemDetail(for: item),
                            isSelected: item.id == selectedItemID
                        )
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private static func itemDetail(for item: ClothingItem) -> String {
        let parts = [
            item.brand,
            ClothingInference.color(for: item),
            ClothingInference.pattern(for: item)
        ]
        .filter { !$0.isEmpty }

        return parts.isEmpty ? item.category.displayName : parts.joined(separator: " · ")
    }
}

private struct BuilderClosetItemRow: View {
    var name: String
    var imageName: String
    var detail: String
    var isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: imageName)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(isSelected ? .semibold : .regular))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
    }
}
