import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                OutfitHistoryView()
            } label: {
                Label("Outfit History", systemImage: "calendar")
            }

            NavigationLink {
                StylePreferencesView()
            } label: {
                Label("Style Preferences", systemImage: "person.crop.square")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("More")
    }
}
