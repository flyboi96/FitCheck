import Foundation

struct AIClothingItemPayload: Codable {
    var id: UUID
    var name: String
    var category: String
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
        category = item.category.rawValue
        color = item.color
        pattern = item.pattern
        formalityLevel = item.formalityLevel
        weatherSuitability = item.weatherSuitability
        occasionSuitability = item.occasionSuitability
        activitySuitability = item.activitySuitability
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
    var recentFeedback: [String]
}

struct AIOutfitResponse: Codable {
    var itemIDs: [UUID]
    var rationale: String
    var cautions: [String]
}

protocol OutfitAIClient {
    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse
}

enum OutfitAIClientError: LocalizedError {
    case proxyNotConfigured
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .proxyNotConfigured:
            "AI proxy is not configured."
        case .invalidResponse:
            "The AI proxy response could not be read."
        }
    }
}

struct DisabledOutfitAIClient: OutfitAIClient {
    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse {
        throw OutfitAIClientError.proxyNotConfigured
    }
}

struct BackendOutfitAIClient: OutfitAIClient {
    var baseURL: URL
    var session: URLSession = .shared

    func suggestOutfit(request: AIOutfitRequest) async throws -> AIOutfitResponse {
        let endpoint = baseURL.appending(path: "outfit-recommendation")
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw OutfitAIClientError.invalidResponse
        }
        return try JSONDecoder().decode(AIOutfitResponse.self, from: data)
    }
}
