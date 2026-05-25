import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ClothingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let item: ClothingItem?

    @State private var name: String
    @State private var category: ClothingCategory
    @State private var notes: String
    @State private var status: ClothingStatus
    @State private var photoData: Data?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var photoStatusMessage = ""

    init(item: ClothingItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? .shirt)
        _notes = State(initialValue: item?.notes ?? "")
        _status = State(initialValue: item?.status ?? .active)
        _photoData = State(initialValue: item?.photoData)
    }

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

                if photoData != nil {
                    Button(role: .destructive) {
                        photoData = nil
                    } label: {
                        Label("Remove Photo", systemImage: "trash")
                    }
                }

                if !photoStatusMessage.isEmpty {
                    Text(photoStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Item") {
                TextField("Blue merino wool button-down", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Category", selection: $category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                Picker("Status", selection: $status) {
                    ForEach(ClothingStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 96)
            }
        }
        .navigationTitle(item == nil ? "Add Item" : "Edit Item")
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
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let inferred = ClothingInference.metadata(name: trimmedName, category: category)

        if let item {
            item.name = trimmedName
            item.category = category
            item.color = inferred.color
            item.pattern = inferred.pattern
            item.formalityLevel = inferred.formalityLevel
            item.weatherSuitability = inferred.weatherSuitability
            item.occasionSuitability = inferred.occasionSuitability
            item.activitySuitability = inferred.activitySuitability
            item.notes = notes
            item.photoData = photoData
            item.status = status
            item.updatedAt = Date()
        } else {
            let newItem = ClothingItem(
                name: trimmedName,
                category: category,
                color: inferred.color,
                pattern: inferred.pattern,
                formalityLevel: inferred.formalityLevel,
                weatherSuitability: inferred.weatherSuitability,
                occasionSuitability: inferred.occasionSuitability,
                activitySuitability: inferred.activitySuitability,
                notes: notes,
                photoData: photoData,
                status: status
            )
            modelContext.insert(newItem)
        }

        try? modelContext.save()
        dismiss()
    }

    @MainActor
    private func loadPhotoItem(_ item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let rawData = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: rawData),
                  let preparedData = image.fitcheckPreparedJPEGData()
            else {
                photoStatusMessage = "Photo could not be loaded."
                return
            }
            photoData = preparedData
            photoStatusMessage = ""
        } catch {
            photoStatusMessage = "Photo load failed: \(error.localizedDescription)"
        }
    }

    private func useCameraImage(_ image: UIImage) {
        guard let preparedData = image.fitcheckPreparedJPEGData() else {
            photoStatusMessage = "Photo could not be prepared."
            return
        }
        photoData = preparedData
        photoStatusMessage = ""
    }
}
