import SwiftUI

struct SettingsView: View {
    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckWeatherFallbackLatitude") private var fallbackLatitude = WeatherLookupFallback.default.latitude
    @AppStorage("fitcheckWeatherFallbackLongitude") private var fallbackLongitude = WeatherLookupFallback.default.longitude

    var body: some View {
        Form {
            Section("Weather") {
                TextField("Fallback location", text: $fallbackName)
                    .textInputAutocapitalization(.words)
                TextField("Latitude", value: $fallbackLatitude, format: .number)
                    .keyboardType(.decimalPad)
                TextField("Longitude", value: $fallbackLongitude, format: .number)
                    .keyboardType(.decimalPad)
                Text("FitCheck uses your current location when allowed, then falls back to these coordinates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Brain") {
                Toggle("AI Enhancements", isOn: $useAIProxy)
                TextField("Proxy endpoint", text: $aiProxyURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("App") {
                LabeledContent("Storage", value: "Local")
                LabeledContent("Version", value: "1.0")
            }
        }
        .navigationTitle("Settings")
    }
}
