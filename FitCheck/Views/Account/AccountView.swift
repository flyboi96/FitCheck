import SwiftData
import SwiftUI

struct AccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var stylePreferences: [StylePreference]
    @Query(sort: \ClothingItem.name) private var closetItems: [ClothingItem]

    @AppStorage("fitcheckWearerProfile") private var wearerProfile = WearerProfileOption.unspecified.rawValue

    @StateObject private var accountStore = FirebaseAccountStore()
    @State private var authMode: AuthMode = .register
    @State private var draft = AccountProfileDraft()
    @State private var statusMessage = ""
    @State private var cloudClosetStatus = ""
    @State private var isPasswordVisible = false

    var body: some View {
        Group {
            if !accountStore.isConfigured {
                firebaseSetupView
            } else if accountStore.account == nil {
                authForm
            } else {
                profileForm
            }
        }
        .navigationTitle("Account")
        .onAppear {
            seedDraftIfNeeded()
        }
        .onChange(of: accountStore.profile) { _, profile in
            if let profile {
                draft = AccountProfileDraft(profile: profile)
                applyLocalProfileDraft(draft)
            }
        }
    }

    private var firebaseSetupView: some View {
        List {
            Section("Firebase Setup") {
                Label("Not configured", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Text("Create a Firebase iOS app for bundle ID `com.alexcorbin.personal.FitCheck`, enable Email/Password sign-in, create a Firestore database, then add `GoogleService-Info.plist` to the FitCheck app target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data Model") {
                LabeledContent("Collection", value: "users")
                LabeledContent("Document ID", value: "Firebase user UID")
                Text("The first synced document stores name, gender, style preferences, and account email. Closet sync can build on this user document next.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var authForm: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $authMode) {
                    ForEach(AuthMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(authMode.displayName) {
                TextField("Email", text: $draft.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                passwordField

                if authMode == .register {
                    TextField("Name", text: $draft.displayName)
                        .textInputAutocapitalization(.words)
                    Picker("Gender", selection: $draft.gender) {
                        ForEach(WearerProfileOption.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                }
            }

            if authMode == .register {
                styleProfileFields
            }

            Section {
                Button {
                    Task {
                        await submitAuth()
                    }
                } label: {
                    if accountStore.isLoading {
                        ProgressView()
                    } else {
                        Text(authMode.actionTitle)
                    }
                }
                .disabled(!canSubmitAuth)

                statusMessages
            }
        }
    }

    private var passwordField: some View {
        HStack {
            Group {
                if isPasswordVisible {
                    TextField("Password", text: $draft.password)
                } else {
                    SecureField("Password", text: $draft.password)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isPasswordVisible.toggle()
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
        }
    }

    private var profileForm: some View {
        Form {
            Section("Account") {
                if let account = accountStore.account {
                    LabeledContent("Email", value: account.email)
                }
                Button(role: .destructive) {
                    accountStore.signOut()
                    statusMessage = "Signed out."
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("Profile") {
                TextField("Name", text: $draft.displayName)
                    .textInputAutocapitalization(.words)
                Picker("Gender", selection: $draft.gender) {
                    ForEach(WearerProfileOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
            }

            styleProfileFields

            Section("Cloud Personalization") {
                LabeledContent("Local closet", value: "\(closetItems.count) item\(closetItems.count == 1 ? "" : "s")")

                Button {
                    Task {
                        await uploadCloset()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: accountStore.isLoading ? "Uploading Closet" : "Upload Closet Metadata",
                        systemImage: "icloud.and.arrow.up",
                        isLoading: accountStore.isLoading
                    )
                }
                .disabled(accountStore.isLoading || closetItems.isEmpty)

                Button {
                    Task {
                        await downloadCloset()
                    }
                } label: {
                    FitCheckButtonLabel(
                        title: accountStore.isLoading ? "Downloading Closet" : "Download Closet Metadata",
                        systemImage: "icloud.and.arrow.down",
                        isLoading: accountStore.isLoading
                    )
                }
                .disabled(accountStore.isLoading)

                Text("This stores your clothing names, categories, quantities, wear counts, and style metadata under your signed-in Firestore user. Photos stay local for now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !cloudClosetStatus.isEmpty {
                    Text(cloudClosetStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    Task {
                        await saveProfile()
                    }
                } label: {
                    if accountStore.isLoading {
                        ProgressView()
                    } else {
                        Label("Save Profile", systemImage: "icloud.and.arrow.up")
                    }
                }
                .disabled(accountStore.isLoading)

                statusMessages
            } footer: {
                Text("Saving writes your profile to Firestore and applies the same style preferences locally for outfit recommendations.")
            }
        }
    }

    private var styleProfileFields: some View {
        Section("Style Preferences") {
            DisclosureGroup("What these mean") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Style summary: the overall vibe FitCheck should aim for.")
                    Text("Favorite looks: outfits or references you tend to like.")
                    Text("Preferred colors and fit: what usually feels natural on you.")
                    Text("Boldness: how experimental recommendations should be.")
                    Text("Disliked combinations and rules: hard no's the app should avoid.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Style summary")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.styleDescription)
                    .frame(minHeight: 80)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Favorite looks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.favoriteLooks)
                    .frame(minHeight: 80)
            }

            TextField("Preferred colors", text: $draft.preferredColors)
                .textInputAutocapitalization(.sentences)
            TextField("Preferred fit", text: $draft.preferredFit)
                .textInputAutocapitalization(.sentences)

            Stepper(value: $draft.boldness, in: 1...5) {
                LabeledContent("Boldness", value: "\(draft.boldness)/5")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Disliked combinations")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.dislikedCombinations)
                    .frame(minHeight: 80)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $draft.rules)
                    .frame(minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private var statusMessages: some View {
        if !accountStore.errorMessage.isEmpty {
            Text(accountStore.errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if !statusMessage.isEmpty {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canSubmitAuth: Bool {
        !accountStore.isLoading &&
        draft.email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@") &&
        draft.password.count >= 6
    }

    private func submitAuth() async {
        let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
        statusMessage = ""

        switch authMode {
        case .register:
            await accountStore.register(email: email, password: draft.password, draft: draft)
            if accountStore.errorMessage.isEmpty {
                applyLocalProfileDraft(draft)
                statusMessage = "Account created and profile saved."
            }
        case .signIn:
            await accountStore.signIn(email: email, password: draft.password)
            if accountStore.errorMessage.isEmpty {
                statusMessage = "Signed in."
            }
        }
    }

    private func saveProfile() async {
        statusMessage = ""
        await accountStore.saveCurrentProfile(draft)

        if accountStore.errorMessage.isEmpty {
            applyLocalProfileDraft(draft)
            statusMessage = "Profile saved."
        }
    }

    private func uploadCloset() async {
        cloudClosetStatus = ""
        let success = await accountStore.uploadClothingItems(closetItems)
        if success {
            cloudClosetStatus = "Uploaded \(closetItems.count) closet item\(closetItems.count == 1 ? "" : "s")."
        }
    }

    private func downloadCloset() async {
        cloudClosetStatus = ""
        let cloudItems = await accountStore.fetchClothingItems()
        guard accountStore.errorMessage.isEmpty else { return }

        var updatedCount = 0
        var insertedCount = 0

        for cloudItem in cloudItems {
            if let localItem = closetItems.first(where: { $0.id == cloudItem.id }) {
                cloudItem.apply(to: localItem)
                updatedCount += 1
            } else {
                modelContext.insert(cloudItem.model)
                insertedCount += 1
            }
        }

        try? modelContext.save()
        cloudClosetStatus = "Downloaded \(cloudItems.count) item\(cloudItems.count == 1 ? "" : "s"): \(insertedCount) new, \(updatedCount) updated."
    }

    private func seedDraftIfNeeded() {
        guard draft.email.isEmpty, draft.displayName.isEmpty else { return }

        if let profile = accountStore.profile {
            draft = AccountProfileDraft(profile: profile)
        } else {
            draft = AccountProfileDraft(
                email: accountStore.account?.email ?? "",
                preference: stylePreferences.first,
                gender: currentWearerProfile
            )
        }
    }

    private func applyLocalProfileDraft(_ draft: AccountProfileDraft) {
        wearerProfile = draft.gender.rawValue

        let preference = stylePreferences.first ?? StylePreference()
        if stylePreferences.isEmpty {
            modelContext.insert(preference)
        }

        preference.styleDescription = draft.styleDescription
        preference.favoriteLooks = draft.favoriteLooks
        preference.dislikedCombinations = draft.dislikedCombinations
        preference.preferredColors = draft.preferredColors
        preference.boldness = draft.boldness
        preference.preferredFit = draft.preferredFit
        preference.rules = draft.rules
        preference.updatedAt = Date()
        try? modelContext.save()
    }

    private var currentWearerProfile: WearerProfileOption {
        WearerProfileOption(rawValue: wearerProfile) ?? .unspecified
    }
}

private enum AuthMode: String, CaseIterable, Identifiable {
    case register
    case signIn

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .register: "Register"
        case .signIn: "Sign In"
        }
    }

    var actionTitle: String {
        switch self {
        case .register: "Create Account"
        case .signIn: "Sign In"
        }
    }
}
