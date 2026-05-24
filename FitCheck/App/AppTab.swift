import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case closet
    case builder
    case trips
    case more

    var id: String { rawValue }

    static var primaryTabs: [AppTab] {
        [.today, .closet, .builder, .trips, .more]
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
            Label("Builder", systemImage: "wand.and.stars")
        case .trips:
            Label("Trips", systemImage: "suitcase.rolling")
        case .more:
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}
