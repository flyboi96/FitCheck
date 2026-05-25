import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct WardrobePhotoImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var userDescription = ""
    @State private var draftName = ""
    @State private var draftCategory: ClothingCategory = .shirt
    @State private var draftQuantity = 1
    @State private var draftNotes = ""
    @State private var aiSuggestion: AIClothingImportResponse?
    @State private var isAnalyzing = false
    @State private var statusMessage = ""
    @State private var showingCamera = false

    var body: some View {
        Form {
            Section("Photo") {
                FitCheckPhotoPreview(data: photoData)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
            }

            Section("Optional Description") {
                TextEditor(text: $userDescription)
                    .frame(minHeight: 80)
            }

            Section("AI Import") {
                Button {
                    Task {
                        await describeWithAI()
                    }
                } label: {
                    if isAnalyzing {
                        Label("Describing Item", systemImage: "sparkles")
                    } else {
                        Label("Describe with AI", systemImage: "sparkles")
                    }
                }
                .disabled(!canDescribeWithAI)

                if isAnalyzing {
                    ProgressView()
                }

                if aiProxyHelpText != nil {
                    Text(aiProxyHelpText ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Review Item") {
                TextField("Blue merino wool button-down", text: $draftName)
                    .textInputAutocapitalization(.words)

                Picker("Category", selection: $draftCategory) {
                    ForEach(availableCategories) { category in
                        Text(category.displayName).tag(category)
                    }
                }

                Stepper(value: $draftQuantity, in: 1...99) {
                    LabeledContent("Quantity", value: "\(draftQuantity)")
                }

                TextEditor(text: $draftNotes)
                    .frame(minHeight: 96)

                if let aiSuggestion {
                    DisclosureGroup("AI Details") {
                        VStack(alignment: .leading, spacing: 8) {
                            detailRow("Color", aiSuggestion.color)
                            detailRow("Pattern", aiSuggestion.pattern)
                            detailRow("Weather", aiSuggestion.weatherSuitability)
                            detailRow("Context", aiSuggestion.occasionSuitability)
                            detailRow("Activity", aiSuggestion.activitySuitability)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Photo Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveItem()
                }
                .disabled(!canSave)
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraCaptureView { image in
                useCameraImage(image)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                await loadPhotoItem(newItem)
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            LabeledContent(title, value: value)
        }
    }

    private var canDescribeWithAI: Bool {
        useAIProxy && configuredAIProxyURL != nil && photoData != nil && !isAnalyzing
    }

    private var canSave: Bool {
        photoData != nil && !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var aiProxyHelpText: String? {
        if !useAIProxy {
            return "AI proxy is off in Settings."
        }
        if configuredAIProxyURL == nil {
            return "AI proxy endpoint is missing in Settings."
        }
        if photoData == nil {
            return "Add a photo before requesting an AI description."
        }
        return nil
    }

    private var configuredAIProxyURL: URL? {
        let trimmed = aiProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }

    @MainActor
    private func loadPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let preparedData = image.fitcheckPreparedJPEGData()
            else {
                statusMessage = "Photo could not be loaded."
                return
            }
            applyPhotoData(preparedData)
        } catch {
            statusMessage = "Photo load failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func describeWithAI() async {
        guard let photoData, let baseURL = configuredAIProxyURL else { return }

        isAnalyzing = true
        statusMessage = ""
        defer {
            isAnalyzing = false
        }

        let token = aiProxyToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let client = BackendOutfitAIClient(baseURL: baseURL, proxyToken: token.isEmpty ? nil : token)
        let response: AIClothingImportResponse

        do {
            response = try await client.describeClothingItem(
                request: AIClothingImportRequest(
                    imageBase64: photoData.base64EncodedString(),
                    mimeType: "image/jpeg",
                    userDescription: userDescription,
                    wearerProfile: currentWearerProfile == .unspecified ? "" : currentWearerProfile.displayName
                )
            )
        } catch {
            statusMessage = "AI import failed: \(error.localizedDescription)"
            return
        }

        aiSuggestion = response
        draftName = response.name
        draftCategory = ClothingCategory(rawValue: response.category) ?? .other
        draftNotes = response.notes.isEmpty ? userDescription : response.notes
        statusMessage = "AI description ready."
    }

    private func useCameraImage(_ image: UIImage) {
        guard let preparedData = image.fitcheckPreparedJPEGData() else {
            statusMessage = "Photo could not be prepared."
            return
        }
        applyPhotoData(preparedData)
    }

    private func applyPhotoData(_ data: Data) {
        photoData = data
        aiSuggestion = nil
        statusMessage = ""
    }

    private func saveItem() {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = ClothingInference.metadata(name: trimmedName, category: draftCategory)
        let item = ClothingItem(
            name: trimmedName,
            category: draftCategory,
            quantity: draftQuantity,
            color: preferredValue(fallback.color, aiSuggestion?.color),
            pattern: preferredValue(fallback.pattern, aiSuggestion?.pattern),
            formalityLevel: max(1, min(5, aiSuggestion?.formalityLevel ?? fallback.formalityLevel)),
            weatherSuitability: preferredValue(aiSuggestion?.weatherSuitability, fallback.weatherSuitability),
            occasionSuitability: preferredValue(aiSuggestion?.occasionSuitability, fallback.occasionSuitability),
            activitySuitability: preferredValue(aiSuggestion?.activitySuitability, fallback.activitySuitability),
            notes: draftNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? userDescription : draftNotes,
            photoData: photoData,
            status: .active
        )

        modelContext.insert(item)
        try? modelContext.save()
        dismiss()
    }

    private func preferredValue(_ values: String?...) -> String {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private var availableCategories: [ClothingCategory] {
        let base = ClothingCategory.options(for: currentWearerProfile)
        guard !base.contains(draftCategory) else { return base }
        return base + [draftCategory]
    }
}
