import SwiftData
import SwiftUI
import UIKit

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var items: [ClothingItem]

    @State private var selectedCategory: ClothingCategory?
    @State private var showingAddItem = false
    @State private var showingPhotoImport = false
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
                Menu {
                    Button {
                        showingAddItem = true
                    } label: {
                        Label("Add Manually", systemImage: "square.and.pencil")
                    }

                    Button {
                        showingPhotoImport = true
                    } label: {
                        Label("Import from Photo", systemImage: "camera")
                    }
                } label: {
                    Label("Add", systemImage: "plus")
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
        .sheet(isPresented: $showingPhotoImport) {
            NavigationStack {
                WardrobePhotoImportView()
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
            if let photoData = item.photoData, let uiImage = UIImage(data: photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: iconName)
                    .foregroundStyle(.tint)
                    .frame(width: 44, height: 44)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

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
        case .activewear:
            "figure.run"
        case .underwear:
            "person"
        case .socks:
            "shoeprints.fill"
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
