import SwiftData
import SwiftUI

struct OutfitHistoryView: View {
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @Query(sort: \ClothingItem.name) private var clothingItems: [ClothingItem]

    var body: some View {
        List {
            Section("Outfits") {
                if loggedOutfits.isEmpty {
                    ContentUnavailableView("No Outfits Logged", systemImage: "calendar")
                } else {
                    ForEach(loggedOutfits) { outfit in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(outfit.name)
                                .font(.headline)
                            Text(outfitDetail(outfit))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !outfit.items.isEmpty {
                                Text(outfit.items.compactMap { $0.item?.name }.joined(separator: ", "))
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Item Rotation") {
                ForEach(clothingItems.sorted { $0.wearCount > $1.wearCount }) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name)
                                .font(.body.weight(.medium))
                            Text(lastWornText(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(item.wearCount)")
                            .font(.headline.monospacedDigit())
                    }
                }
            }

            Section("Wear Logs") {
                ForEach(loggedWearLogs) { log in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(log.item?.name ?? "Item")
                            Text(Self.dateFormatter.string(from: log.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let outfit = log.outfit {
                            Text(outfit.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private var loggedOutfits: [Outfit] {
        outfits.filter { outfit in
            guard let wornAt = outfit.wornAt else { return false }
            return wornAt <= Date()
        }
    }

    private var loggedWearLogs: [WearLog] {
        wearLogs.filter { $0.date <= Date() }
    }

    private func outfitDetail(_ outfit: Outfit) -> String {
        [
            outfit.wornAt.map { Self.dateFormatter.string(from: $0) },
            outfit.occasion,
            outfit.weatherSummary,
            outfit.score > 0 ? "Score \(Int(outfit.score))" : nil
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private func lastWornText(for item: ClothingItem) -> String {
        if let lastWornAt = item.lastWornAt {
            return "Last worn \(Self.dateFormatter.string(from: lastWornAt))"
        }
        return "Never worn"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()
}
