import SwiftUI

struct FitCheckRootView: View {
    @State private var selectedTab: AppTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.primaryTabs) { tab in
                NavigationStack {
                    tab.content
                }
                .tabItem { tab.label }
                .tag(tab)
            }
        }
    }
}
