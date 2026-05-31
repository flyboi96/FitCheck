import SwiftData
import SwiftUI

struct TodayOutfitView: View {
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
    @AppStorage("fitcheckContextStyleNotes") private var contextStyleNotes = ""

    @StateObject private var weatherLookup = WeatherLookupController()
    @State private var manualLocationQuery = ""
    @State private var manualWeatherLocation = ""
    @State private var manualWeatherTemperature = "72"
    @State private var manualWeatherWind = "5"
    @State private var manualWeatherHumidity = ""
    @State private var manualWeatherCondition = "Clear"
    @State private var manualWeatherIsRaining = false
    @State private var manualWeatherOverride: WeatherInput?
    @State private var selectedContext = OutfitContextOption.curatedRawValue(for: UserDefaults.standard.string(forKey: "fitcheckDefaultOutfitContext"))
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
    @State private var recommendationStatus = ""
    @State private var noMatchReasons: [String] = []
    @State private var lastAction: TodayUndoAction?
    @State private var feedbackTarget: OutfitRecommendation?
    @State private var editingRecommendation: OutfitRecommendation?

    private let engine = OutfitRecommendationEngine()
    private let historyService = FitCheckHistoryService()

    var body: some View {
        List {
            Section("Today") {
                todayDashboard

                Picker("Context", selection: $selectedContext) {
                    ForEach(OutfitContextOption.curatedOptions) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }

                Button {
                    generateWithVisibleFeedback()
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingLocal ? "Generating Outfit" : "Generate Outfit",
                        systemImage: "wand.and.stars",
                        isLoading: isGeneratingLocal
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasEnoughItemsForOutfit || effectiveWeather == nil || isGeneratingLocal)

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

                if !aiBuildError.isEmpty {
                    Text(aiBuildError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                FitCheckInlineStatus(message: recommendationStatus)
                FitCheckNoMatchDiagnosticsView(reasons: noMatchReasons)
            }

            Section("Weather Details") {
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

            if !hasEnoughItemsForOutfit {
                ContentUnavailableView("Add Closet Items", systemImage: "tshirt", description: Text("FitCheck needs a top or dress, shoes, and either a bottom or dress before it can score outfits."))
            }

            if !recommendations.isEmpty {
                if let lastAction {
                    Section("Last Action") {
                        HStack {
                            Text(lastAction.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if lastAction.canUndo {
                                Button("Undo") {
                                    undoLastAction()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section {
                    ForEach(recommendations) { recommendation in
                        RecommendationCard(
                            recommendation: recommendation,
                            primaryTitle: "Log Wear",
                            onPrimary: { logWear(recommendation, feedbackType: nil) },
                            onGood: { logWear(recommendation, feedbackType: .goodOutfit) },
                            onBad: { recordNegativeFeedback(for: recommendation, type: .badOutfit) },
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
                } header: {
                    Text("Recommendations")
                } footer: {
                    Text("Log Wear records that you wore it. Wore + Liked records the wear and boosts similar outfits. Reject saves negative feedback without logging a wear.")
                }
            }
        }
        .navigationTitle("Today")
        .task {
            if weatherLookup.result == nil {
                refreshWeather()
            }
        }
        .onChange(of: weatherLookup.isLoading) { _, isLoading in
            updateWeatherActionStatus(isLoading: isLoading)
        }
        .sheet(item: $feedbackTarget) { recommendation in
            OutfitFeedbackEditorView(title: "Outfit Feedback") { type, note in
                recordFeedback(for: recommendation, type: type, note: note)
            }
        }
        .sheet(item: $editingRecommendation) { recommendation in
            RecommendationDraftEditorView(
                recommendation: recommendation,
                closetItems: activeItems,
                feedback: feedback,
                stylePreference: stylePreferences.first,
                request: currentRecommendationRequest
            ) { updated in
                saveEditedRecommendation(updated)
            }
        }
    }

    private var activeItems: [ClothingItem] {
        closetItems.filter { $0.status == .active }
    }

    private var hasEnoughItemsForOutfit: Bool {
        let categories = Set(activeItems.map(\.category))
        let hasTop = categories.contains(.shirt) || categories.contains(.blouse) || categories.contains(.sweater)
        let hasDress = categories.contains(.dress)
        let hasBottom = categories.contains(.pants) || categories.contains(.shorts) || categories.contains(.skirt)
        let hasShoes = categories.contains(.shoes) || categories.contains(.heels) || categories.contains(.flats)
        return hasShoes && (hasDress || (hasTop && hasBottom))
    }

    private var currentWeather: WeatherInput {
        effectiveWeather ?? WeatherLookupFallback.defaultWeather
    }

    private var currentRecommendationRequest: RecommendationRequest {
        RecommendationRequest(
            weather: currentWeather,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            selectedItem: nil
        )
    }

    private var effectiveWeather: WeatherInput? {
        manualWeatherOverride ?? weatherLookup.result?.input
    }

    private var todayDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                dashboardMetric(
                    title: "Weather",
                    value: dashboardWeatherText,
                    systemImage: effectiveWeather?.isRaining == true ? "cloud.rain" : "sun.max"
                )
                dashboardMetric(
                    title: "Closet",
                    value: "\(activeItems.count) active",
                    systemImage: "tshirt"
                )
            }

            HStack(alignment: .top, spacing: 12) {
                dashboardMetric(
                    title: "Context",
                    value: currentContext.displayName,
                    systemImage: "calendar.badge.clock"
                )
                dashboardMetric(
                    title: "Comfort",
                    value: dashboardComfortText,
                    systemImage: "thermometer.medium"
                )
            }

            Text(dashboardPersonalLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func dashboardMetric(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var dashboardWeatherText: String {
        guard let weather = effectiveWeather else { return "Not loaded" }
        return "\(Int(weather.temperatureF.rounded()))F\(weather.humidityPercent.map { ", \(Int($0.rounded()))%" } ?? "")"
    }

    private var dashboardComfortText: String {
        stylePreferences.first?.temperatureSensitivity.displayName ?? "Balanced"
    }

    private var dashboardPersonalLine: String {
        let profile = WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
        let profileText = profile == .unspecified ? "No wearer profile" : profile.displayName
        let styleStatus = stylePreferences.first == nil ? "style profile not set" : "style profile active"
        return "\(profileText) · \(styleStatus) · \(recommendations.isEmpty ? "No current outfit generated" : "\(recommendations.count) outfit option\(recommendations.count == 1 ? "" : "s") ready")"
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
                Text("\(result.input.location) · Wind \(Int(result.input.windMph.rounded())) mph\(humidityStatusText(for: result.input)) · \(result.sourceDescription)")
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
        guard effectiveWeather != nil else { return }
        aiReviews = [:]
        aiReviewErrors = [:]
        avatarPreviews = [:]
        avatarPreviewErrors = [:]
        aiBuildError = ""
        let request = RecommendationRequest(
            weather: currentWeather,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            selectedItem: nil
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
            recommendationStatus = "No outfit matched. See blockers below."
        } else {
            noMatchReasons = []
            recommendationStatus = "Generated \(recommendations.count) outfit\(recommendations.count == 1 ? "" : "s")."
        }
    }

    private func generateWithVisibleFeedback() {
        guard !isGeneratingLocal else { return }
        isGeneratingLocal = true
        recommendationStatus = "Generating outfit with local scoring."

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
        guard let baseURL = configuredAIProxyURL, effectiveWeather != nil else { return }

        isAIChoosingOutfit = true
        aiBuildError = ""
        recommendationStatus = "Asking AI to choose from your closet."
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
            let chosenItems = response.itemIDs.compactMap { itemsByID[$0] }
            let request = RecommendationRequest(
                weather: currentWeather,
                occasion: currentContext.occasion,
                activity: currentContext.activity,
                selectedItem: nil
            )

            guard engine.isCompleteOutfit(chosenItems, request: request) else {
                aiBuildError = "AI returned an incomplete outfit. Try Ask AI First again or use Generate Outfit."
                recommendationStatus = "AI returned an incomplete outfit."
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
            recommendationStatus = "AI picked an outfit and FitCheck scored it locally."
        } catch {
            aiBuildError = error.localizedDescription
            recommendationStatus = "AI outfit request failed."
        }
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

    private func logWear(_ recommendation: OutfitRecommendation, feedbackType: FeedbackType?) {
        let outfit = Outfit(
            name: recommendation.title,
            wornAt: Date(),
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            weatherSummary: currentWeather.summary,
            score: recommendation.score,
            rating: feedbackType == .goodOutfit ? 1 : 0
        )
        modelContext.insert(outfit)

        for item in recommendation.items {
            let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
            modelContext.insert(link)
            outfit.items.append(link)

            item.wearCount += 1
            item.lastWornAt = Date()
            item.updatedAt = Date()

            let wearLog = WearLog(date: Date(), item: item, outfit: outfit)
            modelContext.insert(wearLog)
        }

        if let feedbackType {
            let entry = Feedback(type: feedbackType, combinationKey: recommendation.combinationKey, outfit: outfit)
            modelContext.insert(entry)
            outfit.feedback.append(entry)
        }

        try? modelContext.save()
        lastAction = .loggedOutfit(outfit.id, feedbackType == .goodOutfit ? "Logged wear and positive feedback." : "Logged wear.")
        recommendationStatus = "Wear logged."
        generate()
    }

    private func recordNegativeFeedback(for recommendation: OutfitRecommendation, type: FeedbackType) {
        recordFeedback(for: recommendation, type: type, note: "")
    }

    private func recordFeedback(for recommendation: OutfitRecommendation, type: FeedbackType, note: String) {
        let entry = Feedback(type: type, note: note, combinationKey: recommendation.combinationKey)
        modelContext.insert(entry)
        try? modelContext.save()
        lastAction = .feedback(entry.id, "Saved \(type.displayName.lowercased()) feedback.")
        recommendationStatus = "Feedback saved. Similar outfits will be adjusted next time."
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
        recommendationStatus = "Edited outfit and updated the score."
    }

    private func undoLastAction() {
        guard let lastAction else { return }

        do {
            switch lastAction {
            case .loggedOutfit(let outfitID, _):
                if let outfit = try modelContext.fetch(FetchDescriptor<Outfit>()).first(where: { $0.id == outfitID }) {
                    try historyService.deleteOutfit(outfit, context: modelContext)
                }
            case .feedback(let feedbackID, _):
                if let entry = try modelContext.fetch(FetchDescriptor<Feedback>()).first(where: { $0.id == feedbackID }) {
                    try historyService.deleteFeedback(entry, context: modelContext)
                }
            case .message:
                break
            }
            self.lastAction = nil
            generate()
        } catch {
            self.lastAction = .message("Undo failed: \(error.localizedDescription)")
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

    private func avatarPreviewAction(for recommendation: OutfitRecommendation) -> (() -> Void)? {
        let key = recommendation.combinationKey
        if let avatar = avatars.first,
           avatar.latestPreviewCombinationKey == key,
           let previewData = avatar.latestPreviewData {
            return {
                avatarPreviews[key] = previewData
                recommendationStatus = "Reused saved avatar preview."
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
            let response = try await client.suggestOutfit(request: aiRequest(for: recommendation, selectedItemID: nil))
            aiReviews[key] = response
        } catch {
            aiReviewErrors[key] = error.localizedDescription
        }
    }

    @MainActor
    private func generateAvatarPreview(for recommendation: OutfitRecommendation) async {
        guard let baseURL = configuredAIProxyURL, let referencePhoto = avatarReferencePhoto else { return }

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
                    weatherSummary: currentWeather.summary,
                    location: currentWeather.location,
                    backgroundContext: avatarBackgroundContext(for: currentWeather, condition: currentWeatherCondition),
                    wearerProfile: currentWearerProfile.displayName,
                    styleDescription: styleDescription,
                    avatarNotes: avatars.first?.notes ?? "",
                    weatherCondition: currentWeatherCondition,
                    temperatureF: currentWeather.temperatureF,
                    isRaining: currentWeather.isRaining,
                    windMph: currentWeather.windMph,
                    humidityPercent: currentWeather.humidityPercent,
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

    private func aiRequest(for recommendation: OutfitRecommendation, selectedItemID: UUID?) -> AIOutfitRequest {
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
            weatherSummary: currentWeather.summary,
            occasion: currentContext.occasion,
            activity: currentContext.activity,
            styleDescription: styleDescription,
            selectedItemID: nil,
            candidateItemIDs: candidateItemIDs,
            localScore: localScore,
            localNotes: localNotes,
            recentFeedback: feedback.prefix(12).map(feedbackSummary)
        )
    }

    private var styleDescription: String {
        let wearerLine = currentWearerProfile == .unspecified ? nil : "Wearer profile: \(currentWearerProfile.displayName)"
        let contextLine = contextStyleNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Context style notes:\n\(contextStyleNotes)"
        guard let stylePreference = stylePreferences.first else {
            return [wearerLine, contextLine]
                .compactMap { $0 }
                .joined(separator: "\n")
        }
        return [
            wearerLine,
            contextLine,
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
        OutfitContextOption(rawValue: selectedContext) ?? .businessCasual
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private var currentWeatherCondition: String {
        manualWeatherOverride == nil ? weatherLookup.result?.condition ?? "" : manualWeatherCondition
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
}

private enum TodayUndoAction {
    case loggedOutfit(UUID, String)
    case feedback(UUID, String)
    case message(String)

    var message: String {
        switch self {
        case .loggedOutfit(_, let message), .feedback(_, let message), .message(let message):
            message
        }
    }

    var canUndo: Bool {
        switch self {
        case .loggedOutfit, .feedback:
            true
        case .message:
            false
        }
    }
}

private extension WeatherLookupFallback {
    static var defaultWeather: WeatherInput {
        WeatherInput(temperatureF: 72, isRaining: false, windMph: 6, location: Self.default.name)
    }
}
