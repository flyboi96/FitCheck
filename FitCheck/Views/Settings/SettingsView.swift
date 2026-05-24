import SwiftUI

struct SettingsView: View {
    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name

    var body: some View {
        Form {
            Section("Weather") {
                TextField("Default city", text: $fallbackName)
                    .textInputAutocapitalization(.words)
                Text("FitCheck tries current location first. If location access is off, it looks up weather for this city name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Brain") {
                Toggle("Use AI proxy", isOn: $useAIProxy)
                TextField("Proxy endpoint", text: $aiProxyURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Optional. Leave this off until a small backend exists. The iPhone app should call that backend, not store an OpenAI API key.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                LabeledContent("Storage", value: "Local")
                LabeledContent("Version", value: "1.0")
            }
        }
        .navigationTitle("Settings")
    }
}
