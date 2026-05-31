import SwiftData
import SwiftUI

struct OutfitHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query(sort: \WearLog.date, order: .reverse) private var wearLogs: [WearLog]
    @Query(sort: \ClothingItem.name) private var clothingItems: [ClothingItem]

    @State private var isConfirmingClearHistory = false
    @State private var statusMessage = ""

    private let historyService = FitCheckHistoryService()

    var body: some View {
        List {
            Section("Outfits") {
                if loggedOutfits.isEmpty {
                    ContentUnavailableView("No Outfits Logged", systemImage: "calendar")
                } else {
                    ForEach(loggedOutfits) { outfit in
                        HistoryOutfitCard(outfit: outfit, detail: outfitDetail(outfit))
                    }
                    .onDelete(perform: deleteOutfits)
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

            Section("Wear Logs by Item") {
                if wearLogGroups.isEmpty {
                    ContentUnavailableView("No Wear Logs", systemImage: "list.bullet")
                } else {
                    ForEach(wearLogGroups) { group in
                        DisclosureGroup {
                            ForEach(group.logs) { log in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(Self.dateFormatter.string(from: log.date))
                                        if let outfit = log.outfit {
                                            Text(outfit.name)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        } label: {
                            HStack {
                                Text(group.itemName)
                                Spacer()
                                Text("\(group.logs.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isConfirmingClearHistory = true
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(loggedOutfits.isEmpty && loggedWearLogs.isEmpty)
            }
        }
        .confirmationDialog(
            "Clear all outfit history and reset item wear counts?",
            isPresented: $isConfirmingClearHistory,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes logged outfits and wear logs. Your closet items, trips, and standalone feedback stay in place.")
        }
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

    private var wearLogGroups: [WearLogGroup] {
        let grouped = Dictionary(grouping: loggedWearLogs) { log in
            log.item?.id ?? UUID()
        }

        return grouped.compactMap { _, logs in
            guard let firstLog = logs.first else { return nil }
            return WearLogGroup(
                itemID: firstLog.item?.id ?? UUID(),
                itemName: firstLog.item?.name ?? "Unknown item",
                logs: logs.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.itemName.localizedCaseInsensitiveCompare($1.itemName) == .orderedAscending }
    }

    private func deleteOutfits(at offsets: IndexSet) {
        do {
            let targets = offsets.map { loggedOutfits[$0] }
            for outfit in targets {
                try historyService.deleteOutfit(outfit, context: modelContext)
            }
            statusMessage = "Deleted outfit history item."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        do {
            try historyService.clearLoggedHistory(context: modelContext)
            statusMessage = "Cleared outfit history."
        } catch {
            statusMessage = "Clear failed: \(error.localizedDescription)"
        }
    }

    private func outfitDetail(_ outfit: Outfit) -> String {
        [
            outfit.wornAt.map { Self.dateFormatter.string(from: $0) },
            outfit.occasion,
            outfit.weatherSummary,
            outfit.score != 0 ? "Fit \(FitScoreScale.displayQuality(for: outfit.score))/100" : nil
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

private struct WearLogGroup: Identifiable {
    var itemID: UUID
    var itemName: String
    var logs: [WearLog]

    var id: UUID { itemID }
}

private struct HistoryOutfitCard: View {
    var outfit: Outfit
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(outfit.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if outfit.score != 0 {
                    Text("\(FitScoreScale.displayQuality(for: outfit.score))")
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            if !outfit.items.isEmpty {
                VStack(spacing: 6) {
                    ForEach(outfit.items.compactMap(\.item)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.category.systemImageName)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            Text(item.name)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            Text(item.category.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}
