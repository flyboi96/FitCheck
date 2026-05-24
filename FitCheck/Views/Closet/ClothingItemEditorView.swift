import SwiftData
import SwiftUI

struct ClothingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let item: ClothingItem?

    @State private var name: String
    @State private var category: ClothingCategory
    @State private var notes: String
    @State private var status: ClothingStatus

    init(item: ClothingItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? .shirt)
        _notes = State(initialValue: item?.notes ?? "")
        _status = State(initialValue: item?.status ?? .active)
    }

    var body: some View {
        Form {
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
                status: status
            )
            modelContext.insert(newItem)
        }

        try? modelContext.save()
        dismiss()
    }
}
