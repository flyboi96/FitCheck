import SwiftData
import SwiftUI

struct ClothingItemEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let item: ClothingItem?

    @State private var name: String
    @State private var category: ClothingCategory
    @State private var color: String
    @State private var pattern: String
    @State private var formalityLevel: Int
    @State private var weatherSuitability: String
    @State private var occasionSuitability: String
    @State private var activitySuitability: String
    @State private var notes: String
    @State private var status: ClothingStatus

    init(item: ClothingItem?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _category = State(initialValue: item?.category ?? .shirt)
        _color = State(initialValue: item?.color ?? "")
        _pattern = State(initialValue: item?.pattern ?? "")
        _formalityLevel = State(initialValue: item?.formalityLevel ?? 3)
        _weatherSuitability = State(initialValue: item?.weatherSuitability ?? "")
        _occasionSuitability = State(initialValue: item?.occasionSuitability ?? "")
        _activitySuitability = State(initialValue: item?.activitySuitability ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        _status = State(initialValue: item?.status ?? .active)
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                Picker("Category", selection: $category) {
                    ForEach(ClothingCategory.allCases) { category in
                        Text(category.displayName).tag(category)
                    }
                }
                TextField("Color", text: $color)
                    .textInputAutocapitalization(.words)
                TextField("Pattern", text: $pattern)
                    .textInputAutocapitalization(.words)
                Stepper("Formality \(formalityLevel)", value: $formalityLevel, in: 1...5)
                Picker("Status", selection: $status) {
                    ForEach(ClothingStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }
            }

            Section("Suitability") {
                TextField("Weather", text: $weatherSuitability)
                    .textInputAutocapitalization(.sentences)
                TextField("Occasions", text: $occasionSuitability)
                    .textInputAutocapitalization(.sentences)
                TextField("Activities", text: $activitySuitability)
                    .textInputAutocapitalization(.sentences)
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

        if let item {
            item.name = trimmedName
            item.category = category
            item.color = color
            item.pattern = pattern
            item.formalityLevel = formalityLevel
            item.weatherSuitability = weatherSuitability
            item.occasionSuitability = occasionSuitability
            item.activitySuitability = activitySuitability
            item.notes = notes
            item.status = status
            item.updatedAt = Date()
        } else {
            let newItem = ClothingItem(
                name: trimmedName,
                category: category,
                color: color,
                pattern: pattern,
                formalityLevel: formalityLevel,
                weatherSuitability: weatherSuitability,
                occasionSuitability: occasionSuitability,
                activitySuitability: activitySuitability,
                notes: notes,
                status: status
            )
            modelContext.insert(newItem)
        }

        try? modelContext.save()
        dismiss()
    }
}
