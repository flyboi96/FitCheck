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
            Section("Style") {
                TextEditor(text: $preference.styleDescription)
                    .frame(minHeight: 96)
                TextEditor(text: $preference.favoriteLooks)
                    .frame(minHeight: 96)
            }

            Section("Preferences") {
                TextField("Preferred colors", text: $preference.preferredColors)
                    .textInputAutocapitalization(.sentences)
                Stepper("Boldness \(preference.boldness)", value: $preference.boldness, in: 1...5)
                TextField("Preferred fit", text: $preference.preferredFit)
                    .textInputAutocapitalization(.sentences)
            }

            Section("Rules") {
                TextEditor(text: $preference.rules)
                    .frame(minHeight: 96)
                TextEditor(text: $preference.dislikedCombinations)
                    .frame(minHeight: 96)
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
