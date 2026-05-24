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
                ScoringGuideView()
            } label: {
                Label("Scoring", systemImage: "sum")
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

private struct ScoringGuideView: View {
    var body: some View {
        List {
            Section("Starting Point") {
                Text("Every outfit starts at 50 points, then each item and the full combination add or subtract points.")
            }

            Section("Weather") {
                Text("Cold weather rewards wool, merino, fleece, sweaters, jackets, boots, and coats. Hot weather rewards linen, tees, lightweight items, and shorts. Rain rewards rain shells, waterproof items, and weather-safe shoes.")
            }

            Section("Occasion and Activity") {
                Text("The app infers tags from the item name and category. For example, a blue merino wool button-down is treated as better for dinner, work, and date night than a running tee.")
            }

            Section("Rotation") {
                Text("Items worn in the last few days get a strong penalty. Items not worn recently, or never worn, get a small boost.")
            }

            Section("Color") {
                Text("The local engine builds a small palette from item names. Neutral bases, one clear accent, focused palettes, classic pairings like navy with tan, and adjacent colors get boosts. Too many strong accent colors, red with green, and competing patterns lose points.")
            }

            Section("Style and Feedback") {
                Text("Preferred colors and rules from your style profile can add points. Bad feedback on a full combination or item removes points so it is less likely to appear again.")
            }

            Section("AI Review") {
                Text("When the AI proxy is enabled in Settings, recommendation cards can ask the backend for a second opinion. The AI sees the candidate outfit, weather, occasion, style notes, and recent feedback, then returns a short rationale and cautions.")
            }

            Section("Builder") {
                Text("When you build around one item, that selected item gets a large bonus and is forced into the outfit.")
            }
        }
        .navigationTitle("Scoring")
    }
}
