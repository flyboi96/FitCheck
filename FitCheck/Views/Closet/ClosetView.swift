import SwiftData
import SwiftUI
import UIKit

struct ClosetView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClothingItem.name) private var items: [ClothingItem]

    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var selectedCategory: ClothingCategory?
    @State private var showingAddItem = false
    @State private var showingPhotoImport = false
    @State private var showingBulkImport = false
    @State private var editingItem: ClothingItem?
    @State private var searchText = ""
    @State private var selectedUseFilter = ClosetUseFilter.all

    var body: some View {
        List {
            Section("Find Items") {
                HStack {
                    Label("\(filteredItems.count) shown", systemImage: "tshirt")
                    Spacer()
                    Text("\(activeItemCount) active")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as ClothingCategory?)
                    ForEach(availableCategories) { category in
                        Text(category.displayName).tag(Optional(category))
                    }
                }
                .pickerStyle(.menu)

                Picker("Use", selection: $selectedUseFilter) {
                    ForEach(ClosetUseFilter.allCases) { filter in
                        Label(filter.displayName, systemImage: filter.systemImage).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            if groupedCategories.isEmpty {
                ContentUnavailableView("No Matching Items", systemImage: "magnifyingglass")
            } else {
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
        }
        .navigationTitle("Closet")
        .searchable(text: $searchText, prompt: "Search closet")
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

                    Button {
                        showingBulkImport = true
                    } label: {
                        Label("Bulk Import List", systemImage: "list.bullet.clipboard")
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
        .sheet(isPresented: $showingBulkImport) {
            NavigationStack {
                BulkWardrobeImportView()
            }
        }
    }

    private var filteredItems: [ClothingItem] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            guard item.status != .archived else { return false }
            if let selectedCategory {
                guard item.category == selectedCategory else { return false }
            }
            guard selectedUseFilter.matches(item) else { return false }
            guard !search.isEmpty else { return true }
            return searchableText(for: item).localizedCaseInsensitiveContains(search)
        }
    }

    private var groupedItems: [String: [ClothingItem]] {
        Dictionary(grouping: filteredItems) { $0.category.displayName }
    }

    private var groupedCategories: [String] {
        groupedItems.keys.sorted()
    }

    private var availableCategories: [ClothingCategory] {
        let profileCategories = ClothingCategory.options(for: currentWearerProfile)
        let itemCategories = Set(items.map(\.category))
        return ClothingCategory.allCases.filter { profileCategories.contains($0) || itemCategories.contains($0) }
    }

    private var activeItemCount: Int {
        items.filter { $0.status == .active }.count
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }

    private func searchableText(for item: ClothingItem) -> String {
        [
            item.name,
            item.brand,
            item.category.displayName,
            ClothingInference.color(for: item),
            ClothingInference.pattern(for: item),
            item.weatherSuitability,
            item.occasionSuitability,
            item.activitySuitability,
            item.notes,
            item.status.displayName
        ]
        .joined(separator: " ")
    }
}

private enum ClosetUseFilter: String, CaseIterable, Identifiable {
    case all
    case work
    case gym
    case travel
    case casual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: "All Uses"
        case .work: "Work"
        case .gym: "Gym"
        case .travel: "Travel"
        case .casual: "Casual"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .work: "briefcase"
        case .gym: "figure.strengthtraining.traditional"
        case .travel: "airplane"
        case .casual: "figure.walk"
        }
    }

    func matches(_ item: ClothingItem) -> Bool {
        switch self {
        case .all:
            return true
        case .work:
            return matches(item, terms: ["work", "office", "business", "pilot", "flight", "collared", "button-down", "button down", "chino", "loafer", "dress"])
        case .gym:
            return matches(item, terms: ["gym", "workout", "exercise", "running", "run", "lifting", "lift", "training", "athletic", "performance"])
        case .travel:
            return matches(item, terms: ["travel", "walking", "city", "comfortable", "packable", "airport", "flight"])
        case .casual:
            return matches(item, terms: ["casual", "errands", "walking", "tee", "t-shirt", "jeans", "shorts", "sneaker"])
        }
    }

    private func matches(_ item: ClothingItem, terms: [String]) -> Bool {
        let text = [
            item.name,
            item.brand,
            item.category.displayName,
            item.occasionSuitability,
            item.activitySuitability,
            item.notes
        ]
        .joined(separator: " ")
        .lowercased()

        return terms.contains { text.contains($0) }
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
            item.brand.isEmpty ? nil : item.brand,
            item.quantity > 1 ? "Qty \(item.quantity)" : nil,
            item.lastWornAt.map { "Last \(Self.dateFormatter.string(from: $0))" }
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    private var iconName: String {
        item.category.systemImageName
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }()
}
