import Foundation
import SwiftData

enum ClothingCategory: String, CaseIterable, Codable, Identifiable {
    case shirt
    case blouse
    case pants
    case shorts
    case dress
    case skirt
    case shoes
    case heels
    case flats
    case jacket
    case sweater
    case activewear
    case underwear
    case socks
    case belt
    case watch
    case jewelry
    case accessory
    case bag
    case purse
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shirt: "Shirt"
        case .blouse: "Blouse"
        case .pants: "Pants"
        case .shorts: "Shorts"
        case .dress: "Dress"
        case .skirt: "Skirt"
        case .shoes: "Shoes"
        case .heels: "Heels"
        case .flats: "Flats"
        case .jacket: "Jacket"
        case .sweater: "Sweater"
        case .activewear: "Exercise Clothes"
        case .underwear: "Underwear"
        case .socks: "Socks"
        case .belt: "Belt"
        case .watch: "Watch"
        case .jewelry: "Jewelry"
        case .accessory: "Accessory"
        case .bag: "Bag"
        case .purse: "Purse"
        case .other: "Other"
        }
    }

    static func options(for wearerProfile: WearerProfileOption) -> [ClothingCategory] {
        switch wearerProfile {
        case .female:
            return allCases
        case .male:
            return allCases.filter { !$0.isFemaleFocused }
        case .unspecified:
            return allCases
        }
    }

    var isFemaleFocused: Bool {
        switch self {
        case .blouse, .dress, .skirt, .heels, .flats, .jewelry, .purse:
            return true
        case .shirt, .pants, .shorts, .shoes, .jacket, .sweater, .activewear, .underwear, .socks, .belt, .watch, .accessory, .bag, .other:
            return false
        }
    }

    var systemImageName: String {
        switch self {
        case .shirt, .blouse, .sweater:
            return "tshirt"
        case .activewear:
            return "figure.run"
        case .underwear:
            return "person"
        case .socks:
            return "shoeprints.fill"
        case .pants, .shorts, .dress, .skirt:
            return "figure.stand"
        case .shoes, .heels, .flats:
            return "shoeprints.fill"
        case .jacket:
            return "cloud"
        case .belt, .watch, .jewelry, .accessory:
            return "sparkles"
        case .bag, .purse:
            return "bag"
        case .other:
            return "circle"
        }
    }
}

enum WearerProfileOption: String, CaseIterable, Codable, Identifiable {
    case unspecified
    case male
    case female

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unspecified: "Not Set"
        case .male: "Male"
        case .female: "Female"
        }
    }
}

enum ClothingStatus: String, CaseIterable, Codable, Identifiable {
    case active
    case archived
    case laundry
    case unavailable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: "Active"
        case .archived: "Archived"
        case .laundry: "Laundry"
        case .unavailable: "Unavailable"
        }
    }
}

enum FeedbackType: String, CaseIterable, Codable, Identifiable {
    case goodOutfit
    case badOutfit
    case tooFormal
    case tooCasual
    case colorsDoNotWork
    case badForWeather
    case badForOccasion
    case dislikeCombination

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .goodOutfit: "Good outfit"
        case .badOutfit: "Bad outfit"
        case .tooFormal: "Too formal"
        case .tooCasual: "Too casual"
        case .colorsDoNotWork: "Colors do not work"
        case .badForWeather: "Bad for weather"
        case .badForOccasion: "Bad for occasion"
        case .dislikeCombination: "Dislike combination"
        }
    }

    var isNegative: Bool {
        self != .goodOutfit
    }
}

@Model
final class ClothingItem: Identifiable {
    var id: UUID
    var name: String
    var brand: String = ""
    var categoryRawValue: String
    var quantity: Int = 1
    var color: String
    var pattern: String
    var formalityLevel: Int
    var weatherSuitability: String
    var occasionSuitability: String
    var activitySuitability: String
    var notes: String
    var photoData: Data?
    var statusRawValue: String
    var createdAt: Date
    var updatedAt: Date
    var lastWornAt: Date?
    var wearCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        brand: String = "",
        category: ClothingCategory,
        quantity: Int = 1,
        color: String = "",
        pattern: String = "",
        formalityLevel: Int = 3,
        weatherSuitability: String = "",
        occasionSuitability: String = "",
        activitySuitability: String = "",
        notes: String = "",
        photoData: Data? = nil,
        status: ClothingStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastWornAt: Date? = nil,
        wearCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.categoryRawValue = category.rawValue
        self.quantity = max(1, quantity)
        self.color = color
        self.pattern = pattern
        self.formalityLevel = formalityLevel
        self.weatherSuitability = weatherSuitability
        self.occasionSuitability = occasionSuitability
        self.activitySuitability = activitySuitability
        self.notes = notes
        self.photoData = photoData
        self.statusRawValue = status.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastWornAt = lastWornAt
        self.wearCount = wearCount
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var status: ClothingStatus {
        get { ClothingStatus(rawValue: statusRawValue) ?? .active }
        set { statusRawValue = newValue.rawValue }
    }
}

@Model
final class Outfit: Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var wornAt: Date?
    var occasion: String
    var activity: String
    var weatherSummary: String
    var score: Double
    var rating: Int
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \OutfitItemLink.outfit)
    var items: [OutfitItemLink]
    @Relationship(deleteRule: .cascade, inverse: \Feedback.outfit)
    var feedback: [Feedback]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        wornAt: Date? = nil,
        occasion: String = "",
        activity: String = "",
        weatherSummary: String = "",
        score: Double = 0,
        rating: Int = 0,
        notes: String = "",
        items: [OutfitItemLink] = [],
        feedback: [Feedback] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.wornAt = wornAt
        self.occasion = occasion
        self.activity = activity
        self.weatherSummary = weatherSummary
        self.score = score
        self.rating = rating
        self.notes = notes
        self.items = items
        self.feedback = feedback
    }
}

@Model
final class OutfitItemLink: Identifiable {
    var id: UUID
    var slot: String
    var outfit: Outfit?
    var item: ClothingItem?

    init(id: UUID = UUID(), slot: String, outfit: Outfit? = nil, item: ClothingItem? = nil) {
        self.id = id
        self.slot = slot
        self.outfit = outfit
        self.item = item
    }
}

@Model
final class WearLog: Identifiable {
    var id: UUID
    var date: Date
    var notes: String
    var item: ClothingItem?
    var outfit: Outfit?

    init(id: UUID = UUID(), date: Date = Date(), notes: String = "", item: ClothingItem? = nil, outfit: Outfit? = nil) {
        self.id = id
        self.date = date
        self.notes = notes
        self.item = item
        self.outfit = outfit
    }
}

@Model
final class Feedback: Identifiable {
    var id: UUID
    var createdAt: Date
    var typeRawValue: String
    var note: String
    var combinationKey: String
    var outfit: Outfit?
    var item: ClothingItem?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        type: FeedbackType,
        note: String = "",
        combinationKey: String = "",
        outfit: Outfit? = nil,
        item: ClothingItem? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.typeRawValue = type.rawValue
        self.note = note
        self.combinationKey = combinationKey
        self.outfit = outfit
        self.item = item
    }

    var type: FeedbackType {
        get { FeedbackType(rawValue: typeRawValue) ?? .badOutfit }
        set { typeRawValue = newValue.rawValue }
    }
}

@Model
final class StylePreference: Identifiable {
    var id: UUID
    var styleDescription: String
    var favoriteLooks: String
    var dislikedCombinations: String
    var preferredColors: String
    var boldness: Int
    var preferredFit: String
    var rules: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        styleDescription: String = "",
        favoriteLooks: String = "",
        dislikedCombinations: String = "",
        preferredColors: String = "",
        boldness: Int = 3,
        preferredFit: String = "",
        rules: String = "",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.styleDescription = styleDescription
        self.favoriteLooks = favoriteLooks
        self.dislikedCombinations = dislikedCombinations
        self.preferredColors = preferredColors
        self.boldness = boldness
        self.preferredFit = preferredFit
        self.rules = rules
        self.updatedAt = updatedAt
    }
}

@Model
final class UserAvatar: Identifiable {
    var id: UUID
    var sourcePhotoData: Data?
    var avatarImageData: Data?
    var latestPreviewData: Data?
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        sourcePhotoData: Data? = nil,
        avatarImageData: Data? = nil,
        latestPreviewData: Data? = nil,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourcePhotoData = sourcePhotoData
        self.avatarImageData = avatarImageData
        self.latestPreviewData = latestPreviewData
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
final class Trip: Identifiable {
    var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date
    var notes: String
    var laundryIntervalDays: Int = 0
    var wearsBeforeWash: Int = 1
    var topWearsBeforeWash: Int = 1
    var bottomWearsBeforeWash: Int = 3
    var sweaterWearsBeforeWash: Int = 3
    var jacketWearsBeforeWash: Int = 5
    var activewearWearsBeforeWash: Int = 1
    @Relationship(deleteRule: .cascade, inverse: \TripStop.trip)
    var stops: [TripStop]
    @Relationship(deleteRule: .cascade, inverse: \PackingList.trip)
    var packingLists: [PackingList]
    @Relationship(deleteRule: .cascade, inverse: \DailyItineraryOutfit.trip)
    var itineraryOutfits: [DailyItineraryOutfit]

    init(
        id: UUID = UUID(),
        title: String,
        startsAt: Date,
        endsAt: Date,
        notes: String = "",
        laundryIntervalDays: Int = 0,
        wearsBeforeWash: Int = 1,
        topWearsBeforeWash: Int = 1,
        bottomWearsBeforeWash: Int = 3,
        sweaterWearsBeforeWash: Int = 3,
        jacketWearsBeforeWash: Int = 5,
        activewearWearsBeforeWash: Int = 1,
        stops: [TripStop] = [],
        packingLists: [PackingList] = [],
        itineraryOutfits: [DailyItineraryOutfit] = []
    ) {
        self.id = id
        self.title = title
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.notes = notes
        self.laundryIntervalDays = laundryIntervalDays
        self.wearsBeforeWash = wearsBeforeWash
        self.topWearsBeforeWash = topWearsBeforeWash
        self.bottomWearsBeforeWash = bottomWearsBeforeWash
        self.sweaterWearsBeforeWash = sweaterWearsBeforeWash
        self.jacketWearsBeforeWash = jacketWearsBeforeWash
        self.activewearWearsBeforeWash = activewearWearsBeforeWash
        self.stops = stops
        self.packingLists = packingLists
        self.itineraryOutfits = itineraryOutfits
    }
}

@Model
final class TripStop: Identifiable {
    var id: UUID
    var location: String
    var startsAt: Date
    var endsAt: Date
    var expectedWeather: String
    var customsNotes: String
    var trip: Trip?

    init(
        id: UUID = UUID(),
        location: String,
        startsAt: Date,
        endsAt: Date,
        expectedWeather: String = "",
        customsNotes: String = "",
        trip: Trip? = nil
    ) {
        self.id = id
        self.location = location
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.expectedWeather = expectedWeather
        self.customsNotes = customsNotes
        self.trip = trip
    }
}

@Model
final class PackingList: Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var trip: Trip?
    @Relationship(deleteRule: .cascade, inverse: \PackingListItem.packingList)
    var items: [PackingListItem]

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), trip: Trip? = nil, items: [PackingListItem] = []) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.trip = trip
        self.items = items
    }
}

@Model
final class PackingListItem: Identifiable {
    var id: UUID
    var quantity: Int
    var reason: String
    var item: ClothingItem?
    var packingList: PackingList?

    init(id: UUID = UUID(), quantity: Int = 1, reason: String = "", item: ClothingItem? = nil, packingList: PackingList? = nil) {
        self.id = id
        self.quantity = quantity
        self.reason = reason
        self.item = item
        self.packingList = packingList
    }
}

@Model
final class DailyItineraryOutfit: Identifiable {
    var id: UUID
    var date: Date
    var location: String
    var activity: String
    var trip: Trip?
    var outfit: Outfit?

    init(id: UUID = UUID(), date: Date, location: String, activity: String = "", trip: Trip? = nil, outfit: Outfit? = nil) {
        self.id = id
        self.date = date
        self.location = location
        self.activity = activity
        self.trip = trip
        self.outfit = outfit
    }
}

extension String {
    var fitcheckTags: [String] {
        split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    func fitcheckContainsTag(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return fitcheckTags.contains { tag in
            tag == normalized || normalized.contains(tag) || tag.contains(normalized)
        }
    }
}
