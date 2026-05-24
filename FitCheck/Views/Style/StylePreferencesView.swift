import SwiftData
import SwiftUI

struct StylePreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [StylePreference]

    var body: some View {
        Group {
            if let preference = preferences.first {
                StylePreferenceForm(preference: preference)
            } else {
                ContentUnavailableView {
                    Label("Style Profile", systemImage: "person.crop.square")
                } actions: {
                    Button("Create Profile") {
                        createPreference()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Style")
        .task {
            if preferences.isEmpty {
                createPreference()
            }
        }
    }

    private func createPreference() {
        guard preferences.isEmpty else { return }
        let preference = StylePreference()
        modelContext.insert(preference)
        try? modelContext.save()
    }
}

private struct StylePreferenceForm: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var preference: StylePreference

    var body: some View {
        Form {
            Section("Overall Style") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style summary")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.styleDescription)
                        .frame(minHeight: 96)
                }
            }

            Section("Likes") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Favorite looks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.favoriteLooks)
                        .frame(minHeight: 96)
                }
                TextField("Preferred colors", text: $preference.preferredColors)
                    .textInputAutocapitalization(.sentences)
                TextField("Preferred fit", text: $preference.preferredFit)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Avoid") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disliked combinations")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.dislikedCombinations)
                        .frame(minHeight: 96)
                }
            }

            Section("Rules") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal rules")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $preference.rules)
                        .frame(minHeight: 96)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    preference.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
    }
}
