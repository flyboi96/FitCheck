import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct AvatarStudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserAvatar.updatedAt, order: .reverse) private var avatars: [UserAvatar]
    @Query private var stylePreferences: [StylePreference]

    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var isGeneratingBaseAvatar = false
    @State private var errorMessage = ""
    @State private var avatarStatus = ""

    var body: some View {
        List {
            Section {
                FitCheckPhotoPreview(data: avatar?.sourcePhotoData, height: 420)

                HStack {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Choose Photo", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Reference Photo")
            } footer: {
                Text("Use a clear recent head-to-toe photo when possible. Include hair or hat, neck, hands, legs, and shoes.")
            }

            Section("Avatar") {
                FitCheckPhotoPreview(data: avatar?.avatarImageData ?? avatar?.sourcePhotoData, height: 460)

                if avatar?.avatarImageData != nil {
                    Label("Saved avatar ready", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else if avatar?.sourcePhotoData != nil {
                    Label("Generate once, then outfit previews use the saved avatar", systemImage: "person.crop.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await generateBaseAvatar()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: isGeneratingBaseAvatar ? "Generating Avatar" : "Generate Base Avatar",
                        systemImage: "sparkles",
                        isLoading: isGeneratingBaseAvatar
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canGenerateBaseAvatar)

                FitCheckInlineStatus(
                    message: avatarStatus,
                    isLoading: isGeneratingBaseAvatar
                )

                if !useAIProxy || configuredAIProxyURL == nil {
                    Label("Enable the AI proxy in Settings to generate an avatar.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextEditor(text: notesBinding)
                    .frame(minHeight: 120)
            } header: {
                Text("Avatar Notes")
            } footer: {
                Text("Optional fit, posture, hairstyle, or proportion notes for previews.")
            }
        }
        .navigationTitle("Avatar Studio")
        .task {
            _ = ensureAvatar()
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task {
                await loadSelectedPhoto(newValue)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { image in
                saveSourcePhoto(image)
            }
        }
    }

    private var avatar: UserAvatar? {
        avatars.first
    }

    private var canGenerateBaseAvatar: Bool {
        useAIProxy &&
        configuredAIProxyURL != nil &&
        avatar?.sourcePhotoData != nil &&
        !isGeneratingBaseAvatar
    }

    private var notesBinding: Binding<String> {
        Binding {
            avatar?.notes ?? ""
        } set: { value in
            let avatar = ensureAvatar()
            avatar.notes = value
            avatar.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
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
            stylePreference.rules,
            stylePreference.dislikedCombinations.isEmpty ? nil : "Avoid: \(stylePreference.dislikedCombinations)"
        ]
        .compactMap { $0 }
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }

    @MainActor
    private func ensureAvatar() -> UserAvatar {
        if let avatar {
            return avatar
        }

        let avatar = UserAvatar()
        modelContext.insert(avatar)
        try? modelContext.save()
        return avatar
    }

    @MainActor
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                errorMessage = "That photo could not be read."
                return
            }

            saveSourcePhoto(image)
            selectedPhotoItem = nil
        } catch {
            errorMessage = error.localizedDescription
            avatarStatus = "Photo load failed."
        }
    }

    @MainActor
    private func saveSourcePhoto(_ image: UIImage) {
        guard let data = image.fitcheckPreparedJPEGData(maxDimension: 1600, compressionQuality: 0.82) else {
            errorMessage = "That photo could not be compressed."
            return
        }

        let avatar = ensureAvatar()
        avatar.sourcePhotoData = data
        avatar.avatarImageData = nil
        avatar.latestPreviewData = nil
        avatar.updatedAt = Date()
        try? modelContext.save()
        errorMessage = ""
        avatarStatus = "Reference photo saved."
    }

    @MainActor
    private func generateBaseAvatar() async {
        guard let baseURL = configuredAIProxyURL, let sourcePhotoData = avatar?.sourcePhotoData else { return }

        isGeneratingBaseAvatar = true
        errorMessage = ""
        avatarStatus = "Generating a full-body avatar. This can take a minute."
        defer {
            isGeneratingBaseAvatar = false
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)

        do {
            let response = try await client.generateAvatarPreview(
                request: AIAvatarPreviewRequest(
                    userImageBase64: sourcePhotoData.base64EncodedString(),
                    mimeType: "image/jpeg",
                    outfitItems: [],
                    weatherSummary: "",
                    location: "",
                    backgroundContext: "Simple neutral indoor studio background. Use a camera distance that shows the complete person from hair or hat to shoes.",
                    wearerProfile: currentWearerProfile.displayName,
                    styleDescription: styleDescription,
                    avatarNotes: fullBodyAvatarNotes,
                    usesSavedAvatar: false
                )
            )

            guard let imageData = Data(base64Encoded: response.imageBase64) else {
                errorMessage = "The avatar image could not be decoded."
                avatarStatus = "Avatar generation failed."
                return
            }

            let avatar = ensureAvatar()
            avatar.avatarImageData = imageData
            avatar.latestPreviewData = imageData
            avatar.updatedAt = Date()
            try? modelContext.save()
            avatarStatus = "Full-body avatar saved."
        } catch {
            errorMessage = error.localizedDescription
            avatarStatus = "Avatar generation failed."
        }
    }

    private var fullBodyAvatarNotes: String {
        [
            avatar?.notes ?? "",
            "Critical framing: final avatar must be full body, head-to-toe, including complete hair or hat, neck, hands, lower legs, socks if visible, and complete shoes with margin above and below."
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")
    }
}
