import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            Section("Personal") {
                NavigationLink {
                    AccountView()
                } label: {
                    Label("Account", systemImage: "person.crop.circle")
                }

                NavigationLink {
                    StylePreferencesView()
                } label: {
                    Label("Style Preferences", systemImage: "person.crop.square")
                }

                NavigationLink {
                    AvatarStudioView()
                } label: {
                    Label("Avatar Studio", systemImage: "person.crop.rectangle")
                }
            }

            Section("Records") {
                NavigationLink {
                    OutfitHistoryView()
                } label: {
                    Label("Outfit History", systemImage: "calendar")
                }

                NavigationLink {
                    ScoringGuideView()
                } label: {
                    Label("Scoring", systemImage: "sum")
                }
            }

            Section("App") {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .navigationTitle("More")
    }
}

private struct ScoringGuideView: View {
    var body: some View {
        List {
            Section("Starting Point") {
                Text("Every outfit starts at 50 points, then each item and the full combination add or subtract points. Scores are relative rankings, not percentages. Red means the score is below zero. Socks, belts, watches, and multipack basics no longer get scored like full outfit pieces.")
            }

            Section("Weather") {
                Text("Cold weather rewards wool, merino, fleece, sweaters, jackets, boots, and coats. Hot weather rewards linen, tees, lightweight items, and shorts. Rain rewards rain shells, waterproof items, and weather-safe shoes. Your temperature comfort setting shifts this: if you run hot, warm and humid days push harder toward shorts, tees, and fewer layers.")
            }

            Section("Context") {
                Text("The visible context list is intentionally curated: Business Formal, Business Casual, Smart Casual, Everyday Casual, Hot-Weather Casual, Streetwear, Athleisure, Travel Day, Gym / Training, Running, Lifting, Dinner / Date, and Formal Event. Settings controls the default context used by Today and Build.")
            }

            Section("Dressiness") {
                Text("FitCheck infers dressiness from the item name and category. A blue merino button-down scores better for dinner or work than a running tee because the item name suggests a sharper, more polished piece.")
            }

            Section("Rotation") {
                Text("Items worn in the last few days get a strong penalty. In trip plans, washable clothing is blocked from appearing on back-to-back days. Items not worn recently, or never worn, get a small boost.")
            }

            Section("Color") {
                Text("The local engine builds a small palette from item names. Neutral bases, one clear accent, focused palettes, classic pairings like navy with tan, and adjacent colors get boosts. Too many strong accent colors, red with green, and competing patterns lose points.")
            }

            Section("Style and Feedback") {
                Text("Preferred colors and rules from your style profile can add points without adding filler comments. Statement-piece preferences tell FitCheck and AI when a bold item is welcome. Liked combinations get a boost. Bad feedback on a full combination or item removes points so it is less likely to appear again.")
            }

            Section("Hard Rules") {
                Text("Hard rules apply large score penalties and warnings instead of deleting every option. Current hard rules include no shorts with boots, no sweatpants with boots, no Crocs/clogs/slides/slippers for work, no lounge bottoms with polished tops, no belts without belt-loop bottoms, no work shorts or work sweatpants, and no non-rain-shell jacket in hot humidity.")
            }

            Section("Fashion Gate") {
                Text("The engine builds complete outfits first, then ranks them. Work outfits still get the strongest score when they have a structured work top, tailored bottom, and polished shoe. Bad fashion matches fall to the bottom instead of causing No Outfit Matched.")
            }

            Section("Exercise") {
                Text("Running and lifting are separate contexts. Exercise outfits skip belts and dress accessories, prefer exercise clothes, and can add exercise socks. Packing separates daily underwear/socks from exercise underwear/socks so one item with limited quantity is not overcounted.")
            }

            Section("AI Review") {
                Text("When the AI proxy is enabled in Settings, recommendation cards can ask the backend for a second opinion. The Builder can also ask AI to choose first from the closet. In both cases, the AI sees weather, context, wearer profile, style notes, quantities, and recent feedback, then the app still keeps local scoring visible.")
            }

            Section("Builder") {
                Text("When you build around one item, that selected item gets a large bonus and is forced into the outfit.")
            }
        }
        .navigationTitle("Scoring")
    }
}
