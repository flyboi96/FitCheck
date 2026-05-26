import SwiftData
import SwiftUI

struct StylePreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [StylePreference]

    var body: some View {
        Group {
            if let preference = preferences.first {
                StylePreferenceForm(preference: preference)
            } else {
                ContentUnavailableView {
                    Label("Style Profile", systemImage: "person.crop.square")
                } actions: {
                    Button("Create Profile") {
                        createPreference()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Style")
        .task {
            if preferences.isEmpty {
                createPreference()
            }
        }
    }

    private func createPreference() {
        guard preferences.isEmpty else { return }
        let preference = StylePreference()
        modelContext.insert(preference)
        try? modelContext.save()
    }
}

private struct StylePreferenceForm: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var preference: StylePreference

    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var styleQuestionAnswers = ""
    @State private var isGeneratingProfile = false
    @State private var profileStatus = ""

    var body: some View {
        Form {
            Section("AI Style Coach") {
                DisclosureGroup("Questions to answer") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What outfits make you feel most like yourself?")
                        Text("What do you wear most often now?")
                        Text("What colors, fits, or brands do you usually like?")
                        Text("What feels too flashy, too formal, too casual, or just wrong?")
                        Text("Are there any hard rules FitCheck should follow?")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                TextEditor(text: $styleQuestionAnswers)
                    .frame(minHeight: 120)

                Button {
                    Task {
                        await generateProfileWithAI()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingProfile ? "Building Profile" : "Build Profile from Answers",
                        systemImage: "sparkles",
                        isLoading: isGeneratingProfile
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerateProfile)

                if !useAIProxy || configuredAIProxyURL == nil {
                    Text("Enable the AI proxy in Settings and use the base URL, for example http://127.0.0.1:8787.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !profileStatus.isEmpty {
                    Text(profileStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Overall Style") {
                Text("The overall vibe FitCheck should aim for.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.styleDescription)
                        .frame(minHeight: 96)
                }
            }

            Section("Likes") {
                Text("The looks, colors, and fits that usually work for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Favorite looks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.favoriteLooks)
                        .frame(minHeight: 96)
                }
                TextField("Preferred colors", text: $preference.preferredColors)
                    .textInputAutocapitalization(.sentences)
                TextField("Preferred fit", text: $preference.preferredFit)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Avoid") {
                Text("Specific combinations, colors, fits, or vibes FitCheck should avoid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disliked combinations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.dislikedCombinations)
                        .frame(minHeight: 96)
                }
            }

            Section("Rules") {
                Text("Hard rules that should override generic fashion advice.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.rules)
                        .frame(minHeight: 96)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    preference.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }

    private var canGenerateProfile: Bool {
        useAIProxy &&
        configuredAIProxyURL != nil &&
        !styleQuestionAnswers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isGeneratingProfile
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    @MainActor
    private func generateProfileWithAI() async {
        guard let baseURL = configuredAIProxyURL else { return }

        isGeneratingProfile = true
        profileStatus = "Asking AI to draft your editable style profile."
        defer {
            isGeneratingProfile = false
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.generateStyleProfile(
                request: AIStyleProfileRequest(
                    wearerProfile: (WearerProfileOption(rawValue: wearerProfile) ?? .unspecified).displayName,
                    currentStyleDescription: preference.styleDescription,
                    currentFavoriteLooks: preference.favoriteLooks,
                    currentPreferredColors: preference.preferredColors,
                    currentPreferredFit: preference.preferredFit,
                    currentDislikedCombinations: preference.dislikedCombinations,
                    currentRules: preference.rules,
                    currentBoldness: preference.boldness,
                    questionnaireAnswers: styleQuestionAnswers
                )
            )

            preference.styleDescription = response.styleDescription
            preference.favoriteLooks = response.favoriteLooks
            preference.preferredColors = response.preferredColors
            preference.preferredFit = response.preferredFit
            preference.dislikedCombinations = response.dislikedCombinations
            preference.rules = response.rules
            preference.boldness = response.boldness
            preference.updatedAt = Date()
            try? modelContext.save()
            profileStatus = "Profile draft applied. You can edit anything."
        } catch {
            profileStatus = styleProfileErrorMessage(for: error)
        }
    }

    private func styleProfileErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("not found") {
            return "AI style route not found. Use the base proxy URL in Settings and restart or redeploy the latest backend."
        }
        return message
    }
}
