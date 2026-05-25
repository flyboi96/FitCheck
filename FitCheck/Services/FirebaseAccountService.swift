import Combine
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

struct FitCheckUserAccount: Equatable {
    var uid: String
    var email: String
}

struct CloudUserProfile: Equatable {
    var uid: String
    var email: String
    var displayName: String
    var gender: WearerProfileOption
    var styleDescription: String
    var favoriteLooks: String
    var dislikedCombinations: String
    var preferredColors: String
    var boldness: Int
    var preferredFit: String
    var rules: String
    var createdAt: Date
    var updatedAt: Date

    init(
        uid: String,
        email: String,
        displayName: String = "",
        gender: WearerProfileOption = .unspecified,
        styleDescription: String = "",
        favoriteLooks: String = "",
        dislikedCombinations: String = "",
        preferredColors: String = "",
        boldness: Int = 3,
        preferredFit: String = "",
        rules: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
        self.gender = gender
        self.styleDescription = styleDescription
        self.favoriteLooks = favoriteLooks
        self.dislikedCombinations = dislikedCombinations
        self.preferredColors = preferredColors
        self.boldness = boldness
        self.preferredFit = preferredFit
        self.rules = rules
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(user: User, draft: AccountProfileDraft) {
        self.init(
            uid: user.uid,
            email: user.email ?? draft.email,
            displayName: draft.displayName,
            gender: draft.gender,
            styleDescription: draft.styleDescription,
            favoriteLooks: draft.favoriteLooks,
            dislikedCombinations: draft.dislikedCombinations,
            preferredColors: draft.preferredColors,
            boldness: draft.boldness,
            preferredFit: draft.preferredFit,
            rules: draft.rules
        )
    }

    var firestoreData: [String: Any] {
        [
            "uid": uid,
            "email": email,
            "displayName": displayName,
            "gender": gender.rawValue,
            "styleDescription": styleDescription,
            "favoriteLooks": favoriteLooks,
            "dislikedCombinations": dislikedCombinations,
            "preferredColors": preferredColors,
            "boldness": boldness,
            "preferredFit": preferredFit,
            "rules": rules,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
    }

    static func from(uid: String, email: String, data: [String: Any]) -> CloudUserProfile {
        CloudUserProfile(
            uid: stringValue(data["uid"]) ?? uid,
            email: stringValue(data["email"]) ?? email,
            displayName: stringValue(data["displayName"]) ?? "",
            gender: WearerProfileOption(rawValue: stringValue(data["gender"]) ?? "") ?? .unspecified,
            styleDescription: stringValue(data["styleDescription"]) ?? "",
            favoriteLooks: stringValue(data["favoriteLooks"]) ?? "",
            dislikedCombinations: stringValue(data["dislikedCombinations"]) ?? "",
            preferredColors: stringValue(data["preferredColors"]) ?? "",
            boldness: intValue(data["boldness"]) ?? 3,
            preferredFit: stringValue(data["preferredFit"]) ?? "",
            rules: stringValue(data["rules"]) ?? "",
            createdAt: dateValue(data["createdAt"]) ?? Date(),
            updatedAt: dateValue(data["updatedAt"]) ?? Date()
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Timestamp { return value.dateValue() }
        return nil
    }
}

struct CloudClothingItem: Equatable, Identifiable {
    var id: UUID
    var name: String
    var category: ClothingCategory
    var quantity: Int
    var color: String
    var pattern: String
    var formalityLevel: Int
    var weatherSuitability: String
    var occasionSuitability: String
    var activitySuitability: String
    var notes: String
    var status: ClothingStatus
    var createdAt: Date
    var updatedAt: Date
    var lastWornAt: Date?
    var wearCount: Int

    init(item: ClothingItem) {
        id = item.id
        name = item.name
        category = item.category
        quantity = max(1, item.quantity)
        color = item.color
        pattern = item.pattern
        formalityLevel = item.formalityLevel
        weatherSuitability = item.weatherSuitability
        occasionSuitability = item.occasionSuitability
        activitySuitability = item.activitySuitability
        notes = item.notes
        status = item.status
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastWornAt = item.lastWornAt
        wearCount = item.wearCount
    }

    init(
        id: UUID,
        name: String,
        category: ClothingCategory,
        quantity: Int,
        color: String,
        pattern: String,
        formalityLevel: Int,
        weatherSuitability: String,
        occasionSuitability: String,
        activitySuitability: String,
        notes: String,
        status: ClothingStatus,
        createdAt: Date,
        updatedAt: Date,
        lastWornAt: Date?,
        wearCount: Int
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.quantity = max(1, quantity)
        self.color = color
        self.pattern = pattern
        self.formalityLevel = formalityLevel
        self.weatherSuitability = weatherSuitability
        self.occasionSuitability = occasionSuitability
        self.activitySuitability = activitySuitability
        self.notes = notes
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastWornAt = lastWornAt
        self.wearCount = wearCount
    }

    var firestoreData: [String: Any] {
        var data: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "category": category.rawValue,
            "quantity": quantity,
            "color": color,
            "pattern": pattern,
            "formalityLevel": formalityLevel,
            "weatherSuitability": weatherSuitability,
            "occasionSuitability": occasionSuitability,
            "activitySuitability": activitySuitability,
            "notes": notes,
            "status": status.rawValue,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "wearCount": wearCount
        ]
        if let lastWornAt {
            data["lastWornAt"] = lastWornAt
        }
        return data
    }

    static func from(documentID: String, data: [String: Any]) -> CloudClothingItem? {
        guard let id = UUID(uuidString: stringValue(data["id"]) ?? documentID) else { return nil }
        return CloudClothingItem(
            id: id,
            name: stringValue(data["name"]) ?? "",
            category: ClothingCategory(rawValue: stringValue(data["category"]) ?? "") ?? .other,
            quantity: intValue(data["quantity"]) ?? 1,
            color: stringValue(data["color"]) ?? "",
            pattern: stringValue(data["pattern"]) ?? "",
            formalityLevel: intValue(data["formalityLevel"]) ?? 3,
            weatherSuitability: stringValue(data["weatherSuitability"]) ?? "",
            occasionSuitability: stringValue(data["occasionSuitability"]) ?? "",
            activitySuitability: stringValue(data["activitySuitability"]) ?? "",
            notes: stringValue(data["notes"]) ?? "",
            status: ClothingStatus(rawValue: stringValue(data["status"]) ?? "") ?? .active,
            createdAt: dateValue(data["createdAt"]) ?? Date(),
            updatedAt: dateValue(data["updatedAt"]) ?? Date(),
            lastWornAt: dateValue(data["lastWornAt"]),
            wearCount: intValue(data["wearCount"]) ?? 0
        )
    }

    var model: ClothingItem {
        ClothingItem(
            id: id,
            name: name,
            category: category,
            quantity: quantity,
            color: color,
            pattern: pattern,
            formalityLevel: formalityLevel,
            weatherSuitability: weatherSuitability,
            occasionSuitability: occasionSuitability,
            activitySuitability: activitySuitability,
            notes: notes,
            status: status,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastWornAt: lastWornAt,
            wearCount: wearCount
        )
    }

    func apply(to item: ClothingItem) {
        item.name = name
        item.category = category
        item.quantity = quantity
        item.color = color
        item.pattern = pattern
        item.formalityLevel = formalityLevel
        item.weatherSuitability = weatherSuitability
        item.occasionSuitability = occasionSuitability
        item.activitySuitability = activitySuitability
        item.notes = notes
        item.status = status
        item.createdAt = createdAt
        item.updatedAt = updatedAt
        item.lastWornAt = lastWornAt
        item.wearCount = wearCount
    }

    private static func stringValue(_ value: Any?) -> String? {
        value as? String
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? Date { return value }
        if let value = value as? Timestamp { return value.dateValue() }
        return nil
    }
}

struct AccountProfileDraft: Equatable {
    var email: String = ""
    var password: String = ""
    var displayName: String = ""
    var gender: WearerProfileOption = .unspecified
    var styleDescription: String = ""
    var favoriteLooks: String = ""
    var dislikedCombinations: String = ""
    var preferredColors: String = ""
    var boldness: Int = 3
    var preferredFit: String = ""
    var rules: String = ""

    init() { }

    init(profile: CloudUserProfile) {
        email = profile.email
        displayName = profile.displayName
        gender = profile.gender
        styleDescription = profile.styleDescription
        favoriteLooks = profile.favoriteLooks
        dislikedCombinations = profile.dislikedCombinations
        preferredColors = profile.preferredColors
        boldness = profile.boldness
        preferredFit = profile.preferredFit
        rules = profile.rules
    }

    init(email: String, preference: StylePreference?, gender: WearerProfileOption) {
        self.email = email
        self.gender = gender
        styleDescription = preference?.styleDescription ?? ""
        favoriteLooks = preference?.favoriteLooks ?? ""
        dislikedCombinations = preference?.dislikedCombinations ?? ""
        preferredColors = preference?.preferredColors ?? ""
        boldness = preference?.boldness ?? 3
        preferredFit = preference?.preferredFit ?? ""
        rules = preference?.rules ?? ""
    }
}

enum FirebaseAccountError: LocalizedError {
    case notConfigured
    case noSignedInUser

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Firebase is not configured. Add GoogleService-Info.plist to the FitCheck app target."
        case .noSignedInUser:
            "No Firebase user is signed in."
        }
    }
}

@MainActor
final class FirebaseAccountStore: ObservableObject {
    @Published private(set) var account: FitCheckUserAccount?
    @Published private(set) var profile: CloudUserProfile?
    @Published private(set) var isLoading = false
    @Published var errorMessage = ""

    private var authHandle: AuthStateDidChangeListenerHandle?

    var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    init() {
        guard isConfigured else { return }

        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.account = user.map { FitCheckUserAccount(uid: $0.uid, email: $0.email ?? "") }
                if let user {
                    await self?.loadProfile(for: user)
                } else {
                    self?.profile = nil
                }
            }
        }
    }

    deinit {
        if let authHandle {
            Auth.auth().removeStateDidChangeListener(authHandle)
        }
    }

    func register(email: String, password: String, draft: AccountProfileDraft) async {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let profile = CloudUserProfile(user: result.user, draft: draft)
            try await saveProfile(profile)
            account = FitCheckUserAccount(uid: result.user.uid, email: result.user.email ?? email)
            self.profile = profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            account = FitCheckUserAccount(uid: result.user.uid, email: result.user.email ?? email)
            await loadProfile(for: result.user)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCurrentProfile(_ draft: AccountProfileDraft) async {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return
        }
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = FirebaseAccountError.noSignedInUser.localizedDescription
            return
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let currentCreatedAt = profile?.createdAt ?? Date()
            let profile = CloudUserProfile(
                uid: currentUser.uid,
                email: currentUser.email ?? draft.email,
                displayName: draft.displayName,
                gender: draft.gender,
                styleDescription: draft.styleDescription,
                favoriteLooks: draft.favoriteLooks,
                dislikedCombinations: draft.dislikedCombinations,
                preferredColors: draft.preferredColors,
                boldness: draft.boldness,
                preferredFit: draft.preferredFit,
                rules: draft.rules,
                createdAt: currentCreatedAt,
                updatedAt: Date()
            )
            try await saveProfile(profile)
            self.profile = profile
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uploadClothingItems(_ items: [ClothingItem]) async -> Bool {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return false
        }
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = FirebaseAccountError.noSignedInUser.localizedDescription
            return false
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            for item in items {
                let cloudItem = CloudClothingItem(item: item)
                try await clothingItemsCollection(uid: currentUser.uid)
                    .document(item.id.uuidString)
                    .setData(cloudItem.firestoreData, merge: true)
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fetchClothingItems() async -> [CloudClothingItem] {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return []
        }
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = FirebaseAccountError.noSignedInUser.localizedDescription
            return []
        }

        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let snapshot = try await clothingItemsCollection(uid: currentUser.uid).getDocuments()
            return snapshot.documents.compactMap { document in
                CloudClothingItem.from(documentID: document.documentID, data: document.data())
            }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func signOut() {
        guard isConfigured else {
            errorMessage = FirebaseAccountError.notConfigured.localizedDescription
            return
        }

        do {
            try Auth.auth().signOut()
            account = nil
            profile = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadProfile(for user: User) async {
        isLoading = true
        errorMessage = ""
        defer { isLoading = false }

        do {
            let document = try await profileDocument(uid: user.uid).getDocument()
            if let data = document.data() {
                profile = CloudUserProfile.from(uid: user.uid, email: user.email ?? "", data: data)
            } else {
                let emptyProfile = CloudUserProfile(uid: user.uid, email: user.email ?? "")
                try await saveProfile(emptyProfile)
                profile = emptyProfile
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile(_ profile: CloudUserProfile) async throws {
        try await profileDocument(uid: profile.uid).setData(profile.firestoreData, merge: true)
    }

    private func profileDocument(uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private func clothingItemsCollection(uid: String) -> CollectionReference {
        profileDocument(uid: uid).collection("clothingItems")
    }
}
