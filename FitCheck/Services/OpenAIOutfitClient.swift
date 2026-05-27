import Foundation

struct AIClothingItemPayload: Codable {
    var id: UUID
    var name: String
    var brand: String
    var category: String
    var quantity: Int
    var color: String
    var pattern: String
    var formalityLevel: Int
    var weatherSuitability: String
    var occasionSuitability: String
    var activitySuitability: String
    var notes: String

    init(item: ClothingItem) {
        id = item.id
        name = item.name
        brand = item.brand
        category = item.category.rawValue
        quantity = max(1, item.quantity)
        color = ClothingInference.color(for: item)
        pattern = ClothingInference.pattern(for: item)
        formalityLevel = ClothingInference.formalityLevel(for: item)
        weatherSuitability = ClothingInference.weatherTags(for: item).joined(separator: ", ")
        occasionSuitability = ClothingInference.occasionTags(for: item).joined(separator: ", ")
        activitySuitability = ClothingInference.activityTags(for: item).joined(separator: ", ")
        notes = item.notes
    }
}

struct AIOutfitRequest: Codable {
    var closet: [AIClothingItemPayload]
    var weatherSummary: String
    var occasion: String
    var activity: String
    var styleDescription: String
    var selectedItemID: UUID?
    var candidateItemIDs: [UUID] = []
    var localScore: Double?
    var localNotes: [String] = []
    var recentFeedback: [String] = []
}

struct AIOutfitResponse: Codable {
    var itemIDs: [UUID]
    var rationale: String
    var cautions: [String]
}

struct AIClothingImportRequest: Codable {
    var imageBase64: String
    var mimeType: String
    var userDescription: String
    var wearerProfile: String
}

struct AIClothingImportResponse: Codable {
    var name: String
    var category: String
    var color: String
    var pattern: String
    var formalityLevel: Int
    var weatherSuitability: String
    var occasionSuitability: String
    var activitySuitability: String
    var notes: String
}

struct AIAvatarPreviewRequest: Codable {
    var userImageBase64: String
    var mimeType: String
    var outfitItems: [AIClothingItemPayload]
    var weatherSummary: String
    var location: String
    var backgroundContext: String
    var wearerProfile: String
    var styleDescription: String
    var avatarNotes: String
    var weatherCondition: String = ""
    var temperatureF: Double?
    var isRaining: Bool?
    var windMph: Double?
    var humidityPercent: Double? = nil
    var usesSavedAvatar: Bool = false
}

struct AIAvatarPreviewResponse: Codable {
    var imageBase64: String
    var mimeType: String
    var promptSummary: String
}

struct AIStyleProfileRequest: Codable {
    var wearerProfile: String
    var currentStyleDescription: String
    var currentFavoriteLooks: String
    var currentPreferredColors: String
    var currentPreferredFit: String
    var currentDislikedCombinations: String
    var currentRules: String
    var currentBoldness: Int
    var questionnaireAnswers: String
}

struct AIStyleProfileResponse: Codable {
    var styleDescription: String
    var favoriteLooks: String
    var preferredColors: String
    var preferredFit: String
    var dislikedCombinations: String
    var rules: String
    var boldness: Int
}

protocol OutfitAIClient {
    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse
}

enum OutfitAIClientError: LocalizedError {
    case proxyNotConfigured
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .proxyNotConfigured:
            "AI proxy is not configured."
        case .invalidResponse:
            "The AI proxy response could not be read."
        case .serverMessage(let message):
            message
        }
    }
}

private struct AIProxyErrorResponse: Decodable {
    var error: String
}

struct DisabledOutfitAIClient: OutfitAIClient {
    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse {
        throw OutfitAIClientError.proxyNotConfigured
    }
}

struct BackendOutfitAIClient: OutfitAIClient {
    var baseURL: URL
    var proxyToken: String?
    var session: URLSession = .shared

    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse {
        let endpoint = endpointURL("outfit-recommendation")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let proxyToken, !proxyToken.isEmpty {
            urlRequest.setValue(proxyToken, forHTTPHeaderField: "X-FitCheck-Token")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutfitAIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(statusCode: httpResponse.statusCode, data: data)
        }
        return try JSONDecoder().decode(AIOutfitResponse.self, from: data)
    }

    func describeClothingItem(request: AIClothingImportRequest) async throws -> AIClothingImportResponse {
        let endpoint = endpointURL("clothing-item-description")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let proxyToken, !proxyToken.isEmpty {
            urlRequest.setValue(proxyToken, forHTTPHeaderField: "X-FitCheck-Token")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutfitAIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(statusCode: httpResponse.statusCode, data: data)
        }
        return try JSONDecoder().decode(AIClothingImportResponse.self, from: data)
    }

    func generateAvatarPreview(request: AIAvatarPreviewRequest) async throws -> AIAvatarPreviewResponse {
        let endpoint = endpointURL("avatar-outfit-preview")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let proxyToken, !proxyToken.isEmpty {
            urlRequest.setValue(proxyToken, forHTTPHeaderField: "X-FitCheck-Token")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutfitAIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(statusCode: httpResponse.statusCode, data: data)
        }
        return try JSONDecoder().decode(AIAvatarPreviewResponse.self, from: data)
    }

    func generateStyleProfile(request: AIStyleProfileRequest) async throws -> AIStyleProfileResponse {
        let endpoint = endpointURL("style-profile-draft")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let proxyToken, !proxyToken.isEmpty {
            urlRequest.setValue(proxyToken, forHTTPHeaderField: "X-FitCheck-Token")
        }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OutfitAIClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw proxyError(statusCode: httpResponse.statusCode, data: data)
        }
        return try JSONDecoder().decode(AIStyleProfileResponse.self, from: data)
    }

    private func endpointURL(_ route: String) -> URL {
        var url = baseURL
        let knownRoutes = Set([
            "outfit-recommendation",
            "clothing-item-description",
            "style-profile-draft",
            "avatar-outfit-preview"
        ])

        while knownRoutes.contains(url.lastPathComponent) {
            url.deleteLastPathComponent()
        }

        return url.appending(path: route)
    }

    private func proxyError(statusCode: Int, data: Data) -> OutfitAIClientError {
        if let proxyError = try? JSONDecoder().decode(AIProxyErrorResponse.self, from: data) {
            if statusCode == 404 || proxyError.error.localizedCaseInsensitiveContains("not found") {
                return .serverMessage("AI proxy route not found. In Settings, use the base proxy URL like http://127.0.0.1:8787, then restart or redeploy the latest backend.")
            }
            return .serverMessage(proxyError.error)
        }

        if statusCode == 404 {
            return .serverMessage("AI proxy route not found. Restart or redeploy the latest backend.")
        }

        return .invalidResponse
    }
}
