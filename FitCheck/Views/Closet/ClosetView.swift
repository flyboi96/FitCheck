import SwiftData
import SwiftUI

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var items: [ClothingItem]

    @State private var selectedCategory: ClothingCategory?
    @State private var showingAddItem = false
    @State private var editingItem: ClothingItem?

    var body: some View {
        List {
            Section {
                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as ClothingCategory?)
                    ForEach(ClothingCategory.allCases) { category in
                        Text(category.displayName).tag(Optional(category))
                    }
                }
            }

            ForEach(groupedCategories, id: \.self) { category in
                Section(category) {
                    ForEach(groupedItems[category] ?? []) { item in
                        Button {
                            editingItem = item
                        } label: {
                            ClosetItemRow(item: item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                item.status = .archived
                                item.updatedAt = Date()
                                try? modelContext.save()
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Closet")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddItem) {
            NavigationStack {
                ClothingItemEditorView(item: nil)
            }
        }
        .sheet(item: $editingItem) { item in
            NavigationStack {
                ClothingItemEditorView(item: item)
            }
        }
    }

    private var filteredItems: [ClothingItem] {
        items.filter { item in
            guard item.status != .archived else { return false }
            if let selectedCategory {
                return item.category == selectedCategory
            }
            return true
        }
    }

    private var groupedItems: [String: [ClothingItem]] {
        Dictionary(grouping: filteredItems) { $0.category.displayName }
    }

    private var groupedCategories: [String] {
        groupedItems.keys.sorted()
    }
}

private struct ClosetItemRow: View {
    var item: ClothingItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if item.status != .active {
                Text(item.status.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detailText: String {
        [
            item.category.displayName,
            item.lastWornAt.map { "Last \(Self.dateFormatter.string(from: $0))" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var iconName: String {
        switch item.category {
        case .shirt, .sweater:
            "tshirt"
        case .pants, .shorts:
            "figure.stand"
        case .shoes:
            "shoeprints.fill"
        case .jacket:
            "cloud"
        case .belt, .watch, .accessory:
            "sparkles"
        case .bag:
            "bag"
        case .other:
            "circle"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}
