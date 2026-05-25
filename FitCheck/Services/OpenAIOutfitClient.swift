import Foundation

struct AIClothingItemPayload: Codable {
    var id: UUID
    var name: String
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
        let endpoint = baseURL.appending(path: "outfit-recommendation")
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
            if let proxyError = try? JSONDecoder().decode(AIProxyErrorResponse.self, from: data) {
                throw OutfitAIClientError.serverMessage(proxyError.error)
            }
            throw OutfitAIClientError.invalidResponse
        }
        return try JSONDecoder().decode(AIOutfitResponse.self, from: data)
    }

    func describeClothingItem(request: AIClothingImportRequest) async throws -> AIClothingImportResponse {
        let endpoint = baseURL.appending(path: "clothing-item-description")
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
            if let proxyError = try? JSONDecoder().decode(AIProxyErrorResponse.self, from: data) {
                throw OutfitAIClientError.serverMessage(proxyError.error)
            }
            throw OutfitAIClientError.invalidResponse
        }
        return try JSONDecoder().decode(AIClothingImportResponse.self, from: data)
    }
}
