import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case closet
    case builder
    case trips
    case more

    var id: String { rawValue }

    static var primaryTabs: [AppTab] {
        [.today, .trips, .closet, .builder, .more]
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .today:
            TodayOutfitView()
        case .closet:
            ClosetView()
        case .builder:
            OutfitBuilderView()
        case .trips:
            TripPlannerView()
        case .more:
            MoreView()
        }
    }

    @ViewBuilder
    var label: some View {
        switch self {
        case .today:
            Label("Today", systemImage: "sun.max")
        case .closet:
            Label("Closet", systemImage: "tshirt")
        case .builder:
            Label("Build", systemImage: "wand.and.stars")
        case .trips:
            Label("Plans", systemImage: "calendar")
        case .more:
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}
