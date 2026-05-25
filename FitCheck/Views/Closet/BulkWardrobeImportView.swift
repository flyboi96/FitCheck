import SwiftData
import SwiftUI

struct BulkWardrobeImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var importText = ""
    @State private var statusMessage = ""

    var body: some View {
        Form {
            Section("Wardrobe List") {
                TextEditor(text: $importText)
                    .frame(minHeight: 180)
                    .textInputAutocapitalization(.sentences)

                Text("One item per line. Quantity is optional, such as `10x black boxer briefs`, `3 pairs white athletic socks`, or `navy wrap dress - dress`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Preview") {
                if parsedItems.isEmpty {
                    ContentUnavailableView("No Items Found", systemImage: "list.bullet.clipboard")
                } else {
                    ForEach(parsedItems) { draft in
                        HStack(spacing: 12) {
                            Image(systemName: draft.category.systemImageName)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.name)
                                Text("\(draft.category.displayName) · Qty \(draft.quantity)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Bulk Import")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    importItems()
                }
                .disabled(parsedItems.isEmpty)
            }
        }
    }

    private var parsedItems: [BulkClothingDraft] {
        BulkWardrobeParser.parse(importText, allowedCategories: availableCategories)
    }

    private var availableCategories: [ClothingCategory] {
        ClothingCategory.options(for: currentWearerProfile)
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private func importItems() {
        let drafts = parsedItems
        guard !drafts.isEmpty else { return }

        for draft in drafts {
            let inferred = ClothingInference.metadata(name: draft.name, category: draft.category)
            let item = ClothingItem(
                name: draft.name,
                category: draft.category,
                quantity: draft.quantity,
                color: inferred.color,
                pattern: inferred.pattern,
                formalityLevel: inferred.formalityLevel,
                weatherSuitability: inferred.weatherSuitability,
                occasionSuitability: inferred.occasionSuitability,
                activitySuitability: inferred.activitySuitability
            )
            modelContext.insert(item)
        }

        try? modelContext.save()
        statusMessage = "Imported \(drafts.count) item\(drafts.count == 1 ? "" : "s")."
        dismiss()
    }
}

private struct BulkClothingDraft: Identifiable {
    var id = UUID()
    var name: String
    var category: ClothingCategory
    var quantity: Int
}

private enum BulkWardrobeParser {
    static func parse(_ text: String, allowedCategories: [ClothingCategory]) -> [BulkClothingDraft] {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { parseLine(String($0), allowedCategories: allowedCategories) }
    }

    private static func parseLine(_ line: String, allowedCategories: [ClothingCategory]) -> BulkClothingDraft? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let quantityResult = extractQuantity(from: trimmed)
        let categoryResult = extractExplicitCategory(from: quantityResult.name, allowedCategories: allowedCategories)
        let inferredCategory = categoryResult.category ?? inferCategory(from: categoryResult.name, allowedCategories: allowedCategories)
        let cleanedName = categoryResult.name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanedName.isEmpty else { return nil }

        return BulkClothingDraft(
            name: cleanedName,
            category: inferredCategory,
            quantity: quantityResult.quantity
        )
    }

    private static func extractQuantity(from line: String) -> (quantity: Int, name: String) {
        let pattern = #"^\s*(\d+)\s*(?:x|pairs?\s+of|pair\s+of)?\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return (1, line)
        }

        let nsLine = line as NSString
        let range = NSRange(location: 0, length: nsLine.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1,
              let quantityRange = Range(match.range(at: 1), in: line),
              let matchedRange = Range(match.range, in: line),
              let quantity = Int(line[quantityRange])
        else {
            return (1, line)
        }

        let name = String(line[matchedRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (max(1, min(quantity, 99)), name.isEmpty ? line : name)
    }

    private static func extractExplicitCategory(
        from line: String,
        allowedCategories: [ClothingCategory]
    ) -> (name: String, category: ClothingCategory?) {
        let separators = [" - ", " | ", ": "]

        for separator in separators where line.contains(separator) {
            let parts = line.components(separatedBy: separator)
            guard let possibleCategory = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let category = category(from: possibleCategory, allowedCategories: allowedCategories)
            else {
                continue
            }

            let name = parts.dropLast().joined(separator: separator)
            return (name, category)
        }

        return (line, nil)
    }

    private static func inferCategory(from line: String, allowedCategories: [ClothingCategory]) -> ClothingCategory {
        let text = line.lowercased()
        let orderedMatches: [(ClothingCategory, [String])] = [
            (.underwear, ["underwear", "boxer", "brief"]),
            (.socks, ["sock"]),
            (.activewear, ["gym", "workout", "running", "athletic", "training"]),
            (.heels, ["heel", "pump"]),
            (.flats, ["flat", "loafer"]),
            (.shoes, ["shoe", "sneaker", "boot", "loafer"]),
            (.dress, ["dress", "gown"]),
            (.skirt, ["skirt"]),
            (.blouse, ["blouse"]),
            (.shirt, ["shirt", "tee", "t-shirt", "polo", "button-down", "button down"]),
            (.pants, ["pant", "jean", "chino", "trouser"]),
            (.shorts, ["short"]),
            (.jacket, ["jacket", "coat", "blazer", "shell"]),
            (.sweater, ["sweater", "hoodie", "cardigan", "fleece"]),
            (.belt, ["belt"]),
            (.watch, ["watch"]),
            (.jewelry, ["jewelry", "necklace", "bracelet", "earring", "ring"]),
            (.purse, ["purse", "handbag", "clutch"]),
            (.bag, ["bag", "backpack", "duffel"])
        ]

        for (category, keywords) in orderedMatches
            where allowedCategories.contains(category) && keywords.contains(where: { text.contains($0) }) {
            return category
        }

        return allowedCategories.contains(.other) ? .other : (allowedCategories.first ?? .other)
    }

    private static func category(from text: String, allowedCategories: [ClothingCategory]) -> ClothingCategory? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allowedCategories.first {
            $0.rawValue == normalized || $0.displayName.lowercased() == normalized
        }
    }
}
