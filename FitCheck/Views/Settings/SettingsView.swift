import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @AppStorage("fitcheckUseAIProxy") private var useAIProxy = false
    @AppStorage("fitcheckAIProxyURL") private var aiProxyURL = ""
    @AppStorage("fitcheckAIProxyToken") private var aiProxyToken = ""
    @AppStorage("fitcheckWeatherFallbackName") private var fallbackName = WeatherLookupFallback.default.name
    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @State private var isExportingBackup = false
    @State private var isImportingBackup = false
    @State private var isConfirmingImport = false
    @State private var backupDocument = FitCheckBackupDocument()
    @State private var backupStatus = ""

    private let backupService = FitCheckBackupService()

    var body: some View {
        Form {
            Section("Weather") {
                TextField("Default city", text: $fallbackName)
                    .textInputAutocapitalization(.words)
                Text("FitCheck tries current location first. If location access is off, it looks up weather for this city name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Wearer") {
                Picker("Profile", selection: $wearerProfile) {
                    ForEach(WearerProfileOption.allCases) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                Text("Used as context for AI outfit reviews and future personalization. Keep it unset if you do not want gendered style assumptions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Brain") {
                Toggle("Use AI proxy", isOn: $useAIProxy)
                TextField("Proxy endpoint", text: $aiProxyURL, prompt: Text("http://127.0.0.1:8787"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Proxy token", text: $aiProxyToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Optional. Enter the base proxy URL, not a route. The iPhone app calls your backend proxy for outfit review and photo import. Do not put an OpenAI API key in the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DisclosureGroup("What to enter") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. Put `OPENAI_API_KEY` and `FITCHECK_PROXY_TOKEN` in `backend/.env` on your Mac or server.")
                        Text("2. Start the proxy with `node backend/server.mjs`.")
                        Text("3. In the simulator, use `http://127.0.0.1:8787` as the proxy endpoint.")
                        Text("4. On a physical iPhone, use your Mac/server address, such as `http://192.168.1.25:8787`.")
                        Text("5. Do not add `/outfit-recommendation` or another route to the endpoint.")
                        Text("6. Put the same `FITCHECK_PROXY_TOKEN` in Proxy token.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Backup") {
                Button {
                    exportBackup()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    backupStatus = "Choose a backup file to import."
                    isConfirmingImport = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }

                Text("Exports closet items, outfit history, feedback, style preferences, trips, packing lists, and itinerary feedback as JSON. Import replaces the local FitCheck data on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !backupStatus.isEmpty {
                    Text(backupStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("TestFlight") {
                Label("Release build ready", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                Text("Archive from Xcode with an iPhone device destination, then upload to App Store Connect and add your wife as a TestFlight tester.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Before uploading: confirm Firebase rules are deployed, the AI proxy URL works from a real iPhone, and the build number is higher than any previous TestFlight upload.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("App") {
                LabeledContent("Storage", value: "Local")
                LabeledContent("Version", value: appVersion)
                LabeledContent("Build", value: buildNumber)
            }
        }
        .navigationTitle("Settings")
        .fileExporter(
            isPresented: $isExportingBackup,
            document: backupDocument,
            contentType: .json,
            defaultFilename: "FitCheck Backup"
        ) { result in
            switch result {
            case .success:
                backupStatus = "Backup exported."
            case .failure(let error):
                backupStatus = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.json]
        ) { result in
            importBackup(from: result)
        }
        .confirmationDialog(
            "Importing a backup replaces all local FitCheck data on this device.",
            isPresented: $isConfirmingImport,
            titleVisibility: .visible
        ) {
            Button("Choose Backup File", role: .destructive) {
                isImportingBackup = true
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func exportBackup() {
        do {
            backupStatus = "Preparing backup."
            let data = try backupService.exportData(context: modelContext)
            backupDocument = FitCheckBackupDocument(data: data)
            isExportingBackup = true
        } catch {
            backupStatus = "Export failed: \(error.localizedDescription)"
        }
    }

    private func importBackup(from result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            try backupService.restore(from: data, context: modelContext)
            backupStatus = "Backup imported."
        } catch {
            backupStatus = "Import failed: \(error.localizedDescription)"
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"
    }
}
