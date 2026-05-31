import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FitCheckBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
struct FitCheckBackupService {
    func exportData(context: ModelContext) throws -> Data {
        let backup = FitCheckBackup(
            exportedAt: Date(),
            clothingItems: try context.fetch(FetchDescriptor<ClothingItem>()).map { ClothingItemBackup(item: $0) },
            outfits: try context.fetch(FetchDescriptor<Outfit>()).map { OutfitBackup(outfit: $0) },
            wearLogs: try context.fetch(FetchDescriptor<WearLog>()).map { WearLogBackup(log: $0) },
            feedback: try context.fetch(FetchDescriptor<Feedback>()).map { FeedbackBackup(feedback: $0) },
            stylePreferences: try context.fetch(FetchDescriptor<StylePreference>()).map { StylePreferenceBackup(preference: $0) },
            userAvatars: try context.fetch(FetchDescriptor<UserAvatar>()).map { UserAvatarBackup(avatar: $0) },
            trips: try context.fetch(FetchDescriptor<Trip>()).map { TripBackup(trip: $0) },
            tripStops: try context.fetch(FetchDescriptor<TripStop>()).map { TripStopBackup(stop: $0) },
            packingLists: try context.fetch(FetchDescriptor<PackingList>()).map { PackingListBackup(list: $0) },
            packingListItems: try context.fetch(FetchDescriptor<PackingListItem>()).map { PackingListItemBackup(item: $0) },
            dailyItineraryOutfits: try context.fetch(FetchDescriptor<DailyItineraryOutfit>()).map { DailyItineraryOutfitBackup(itinerary: $0) }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    func restore(from data: Data, context: ModelContext) throws {
        let decoder = JSONDecoder()
        let backup = try decoder.decode(FitCheckBackup.self, from: data)

        try deleteExistingData(context: context)

        var itemByID: [UUID: ClothingItem] = [:]
        var outfitByID: [UUID: Outfit] = [:]
        var tripByID: [UUID: Trip] = [:]
        var packingListByID: [UUID: PackingList] = [:]

        for itemBackup in backup.clothingItems {
            let item = itemBackup.model
            context.insert(item)
            itemByID[item.id] = item
        }

        for outfitBackup in backup.outfits {
            let outfit = outfitBackup.model
            context.insert(outfit)
            outfitByID[outfit.id] = outfit

            for itemID in outfitBackup.itemIDs {
                guard let item = itemByID[itemID] else { continue }
                let link = OutfitItemLink(slot: item.category.displayName, outfit: outfit, item: item)
                context.insert(link)
                outfit.items.append(link)
            }
        }

        for logBackup in backup.wearLogs {
            let log = WearLog(
                id: logBackup.id,
                date: logBackup.date,
                notes: logBackup.notes,
                item: logBackup.itemID.flatMap { itemByID[$0] },
                outfit: logBackup.outfitID.flatMap { outfitByID[$0] }
            )
            context.insert(log)
        }

        for feedbackBackup in backup.feedback {
            let entry = Feedback(
                id: feedbackBackup.id,
                createdAt: feedbackBackup.createdAt,
                type: FeedbackType(rawValue: feedbackBackup.typeRawValue) ?? .badOutfit,
                note: feedbackBackup.note,
                combinationKey: feedbackBackup.combinationKey,
                outfit: feedbackBackup.outfitID.flatMap { outfitByID[$0] },
                item: feedbackBackup.itemID.flatMap { itemByID[$0] }
            )
            context.insert(entry)
            entry.outfit?.feedback.append(entry)
        }

        for preferenceBackup in backup.stylePreferences {
            context.insert(preferenceBackup.model)
        }

        for avatarBackup in backup.userAvatars {
            context.insert(avatarBackup.model)
        }

        for tripBackup in backup.trips {
            let trip = tripBackup.model
            context.insert(trip)
            tripByID[trip.id] = trip
        }

        for stopBackup in backup.tripStops {
            guard let trip = tripByID[stopBackup.tripID] else { continue }
            let stop = stopBackup.model(trip: trip)
            context.insert(stop)
            trip.stops.append(stop)
        }

        for listBackup in backup.packingLists {
            guard let trip = tripByID[listBackup.tripID] else { continue }
            let list = listBackup.model(trip: trip)
            context.insert(list)
            trip.packingLists.append(list)
            packingListByID[list.id] = list
        }

        for itemBackup in backup.packingListItems {
            guard let list = packingListByID[itemBackup.packingListID] else { continue }
            let item = itemBackup.model(
                clothingItem: itemBackup.itemID.flatMap { itemByID[$0] },
                packingList: list
            )
            context.insert(item)
            list.items.append(item)
        }

        for itineraryBackup in backup.dailyItineraryOutfits {
            guard let trip = tripByID[itineraryBackup.tripID] else { continue }
            let itinerary = itineraryBackup.model(
                trip: trip,
                outfit: itineraryBackup.outfitID.flatMap { outfitByID[$0] }
            )
            context.insert(itinerary)
            trip.itineraryOutfits.append(itinerary)
        }

        try context.save()
    }

    private func deleteExistingData(context: ModelContext) throws {
        for model in try context.fetch(FetchDescriptor<DailyItineraryOutfit>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<PackingListItem>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<PackingList>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<TripStop>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<Trip>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<Feedback>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<WearLog>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<OutfitItemLink>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<Outfit>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<StylePreference>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<UserAvatar>()) {
            context.delete(model)
        }
        for model in try context.fetch(FetchDescriptor<ClothingItem>()) {
            context.delete(model)
        }
        try context.save()
    }
}

private struct FitCheckBackup: Codable {
    var version = 1
    var exportedAt: Date
    var clothingItems: [ClothingItemBackup]
    var outfits: [OutfitBackup]
    var wearLogs: [WearLogBackup]
    var feedback: [FeedbackBackup]
    var stylePreferences: [StylePreferenceBackup]
    var userAvatars: [UserAvatarBackup]
    var trips: [TripBackup]
    var tripStops: [TripStopBackup]
    var packingLists: [PackingListBackup]
    var packingListItems: [PackingListItemBackup]
    var dailyItineraryOutfits: [DailyItineraryOutfitBackup]

    init(
        exportedAt: Date,
        clothingItems: [ClothingItemBackup],
        outfits: [OutfitBackup],
        wearLogs: [WearLogBackup],
        feedback: [FeedbackBackup],
        stylePreferences: [StylePreferenceBackup],
        userAvatars: [UserAvatarBackup],
        trips: [TripBackup],
        tripStops: [TripStopBackup],
        packingLists: [PackingListBackup],
        packingListItems: [PackingListItemBackup],
        dailyItineraryOutfits: [DailyItineraryOutfitBackup]
    ) {
        self.exportedAt = exportedAt
        self.clothingItems = clothingItems
        self.outfits = outfits
        self.wearLogs = wearLogs
        self.feedback = feedback
        self.stylePreferences = stylePreferences
        self.userAvatars = userAvatars
        self.trips = trips
        self.tripStops = tripStops
        self.packingLists = packingLists
        self.packingListItems = packingListItems
        self.dailyItineraryOutfits = dailyItineraryOutfits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        clothingItems = try container.decodeIfPresent([ClothingItemBackup].self, forKey: .clothingItems) ?? []
        outfits = try container.decodeIfPresent([OutfitBackup].self, forKey: .outfits) ?? []
        wearLogs = try container.decodeIfPresent([WearLogBackup].self, forKey: .wearLogs) ?? []
        feedback = try container.decodeIfPresent([FeedbackBackup].self, forKey: .feedback) ?? []
        stylePreferences = try container.decodeIfPresent([StylePreferenceBackup].self, forKey: .stylePreferences) ?? []
        userAvatars = try container.decodeIfPresent([UserAvatarBackup].self, forKey: .userAvatars) ?? []
        trips = try container.decodeIfPresent([TripBackup].self, forKey: .trips) ?? []
        tripStops = try container.decodeIfPresent([TripStopBackup].self, forKey: .tripStops) ?? []
        packingLists = try container.decodeIfPresent([PackingListBackup].self, forKey: .packingLists) ?? []
        packingListItems = try container.decodeIfPresent([PackingListItemBackup].self, forKey: .packingListItems) ?? []
        dailyItineraryOutfits = try container.decodeIfPresent([DailyItineraryOutfitBackup].self, forKey: .dailyItineraryOutfits) ?? []
    }
}

private struct ClothingItemBackup: Codable {
    var id: UUID
    var name: String
    var brand: String
    var categoryRawValue: String
    var quantity: Int
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

    init(item: ClothingItem) {
        id = item.id
        name = item.name
        brand = item.brand
        categoryRawValue = item.categoryRawValue
        quantity = max(1, item.quantity)
        color = item.color
        pattern = item.pattern
        formalityLevel = item.formalityLevel
        weatherSuitability = item.weatherSuitability
        occasionSuitability = item.occasionSuitability
        activitySuitability = item.activitySuitability
        notes = item.notes
        photoData = item.photoData
        statusRawValue = item.statusRawValue
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastWornAt = item.lastWornAt
        wearCount = item.wearCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        categoryRawValue = try container.decode(String.self, forKey: .categoryRawValue)
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? ""
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        formalityLevel = try container.decodeIfPresent(Int.self, forKey: .formalityLevel) ?? 3
        weatherSuitability = try container.decodeIfPresent(String.self, forKey: .weatherSuitability) ?? ""
        occasionSuitability = try container.decodeIfPresent(String.self, forKey: .occasionSuitability) ?? ""
        activitySuitability = try container.decodeIfPresent(String.self, forKey: .activitySuitability) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photoData = try container.decodeIfPresent(Data.self, forKey: .photoData)
        statusRawValue = try container.decodeIfPresent(String.self, forKey: .statusRawValue) ?? ClothingStatus.active.rawValue
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastWornAt = try container.decodeIfPresent(Date.self, forKey: .lastWornAt)
        wearCount = try container.decodeIfPresent(Int.self, forKey: .wearCount) ?? 0
    }

    var model: ClothingItem {
        ClothingItem(
            id: id,
            name: name,
            brand: brand,
            category: ClothingCategory(rawValue: categoryRawValue) ?? .other,
            quantity: max(1, quantity),
            color: color,
            pattern: pattern,
            formalityLevel: formalityLevel,
            weatherSuitability: weatherSuitability,
            occasionSuitability: occasionSuitability,
            activitySuitability: activitySuitability,
            notes: notes,
            photoData: photoData,
            status: ClothingStatus(rawValue: statusRawValue) ?? .active,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastWornAt: lastWornAt,
            wearCount: wearCount
        )
    }
}

private struct OutfitBackup: Codable {
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
    var itemIDs: [UUID]

    init(outfit: Outfit) {
        id = outfit.id
        name = outfit.name
        createdAt = outfit.createdAt
        wornAt = outfit.wornAt
        occasion = outfit.occasion
        activity = outfit.activity
        weatherSummary = outfit.weatherSummary
        score = outfit.score
        rating = outfit.rating
        notes = outfit.notes
        itemIDs = outfit.items.compactMap { $0.item?.id }
    }

    var model: Outfit {
        Outfit(
            id: id,
            name: name,
            createdAt: createdAt,
            wornAt: wornAt,
            occasion: occasion,
            activity: activity,
            weatherSummary: weatherSummary,
            score: score,
            rating: rating,
            notes: notes
        )
    }
}

private struct WearLogBackup: Codable {
    var id: UUID
    var date: Date
    var notes: String
    var itemID: UUID?
    var outfitID: UUID?

    init(log: WearLog) {
        id = log.id
        date = log.date
        notes = log.notes
        itemID = log.item?.id
        outfitID = log.outfit?.id
    }
}

private struct FeedbackBackup: Codable {
    var id: UUID
    var createdAt: Date
    var typeRawValue: String
    var note: String
    var combinationKey: String
    var outfitID: UUID?
    var itemID: UUID?

    init(feedback: Feedback) {
        id = feedback.id
        createdAt = feedback.createdAt
        typeRawValue = feedback.typeRawValue
        note = feedback.note
        combinationKey = feedback.combinationKey
        outfitID = feedback.outfit?.id
        itemID = feedback.item?.id
    }
}

private struct StylePreferenceBackup: Codable {
    var id: UUID
    var styleDescription: String
    var favoriteLooks: String
    var dislikedCombinations: String
    var preferredColors: String
    var boldness: Int
    var preferredFit: String
    var temperatureSensitivityRawValue: String
    var statementPiecePreference: String
    var rules: String
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case styleDescription
        case favoriteLooks
        case dislikedCombinations
        case preferredColors
        case boldness
        case preferredFit
        case temperatureSensitivityRawValue
        case statementPiecePreference
        case rules
        case updatedAt
    }

    init(preference: StylePreference) {
        id = preference.id
        styleDescription = preference.styleDescription
        favoriteLooks = preference.favoriteLooks
        dislikedCombinations = preference.dislikedCombinations
        preferredColors = preference.preferredColors
        boldness = preference.boldness
        preferredFit = preference.preferredFit
        temperatureSensitivityRawValue = preference.temperatureSensitivityRawValue
        statementPiecePreference = preference.statementPiecePreference
        rules = preference.rules
        updatedAt = preference.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        styleDescription = try container.decode(String.self, forKey: .styleDescription)
        favoriteLooks = try container.decode(String.self, forKey: .favoriteLooks)
        dislikedCombinations = try container.decode(String.self, forKey: .dislikedCombinations)
        preferredColors = try container.decode(String.self, forKey: .preferredColors)
        boldness = try container.decode(Int.self, forKey: .boldness)
        preferredFit = try container.decode(String.self, forKey: .preferredFit)
        temperatureSensitivityRawValue = try container.decodeIfPresent(String.self, forKey: .temperatureSensitivityRawValue) ?? TemperatureSensitivityOption.balanced.rawValue
        statementPiecePreference = try container.decodeIfPresent(String.self, forKey: .statementPiecePreference) ?? ""
        rules = try container.decode(String.self, forKey: .rules)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var model: StylePreference {
        StylePreference(
            id: id,
            styleDescription: styleDescription,
            favoriteLooks: favoriteLooks,
            dislikedCombinations: dislikedCombinations,
            preferredColors: preferredColors,
            boldness: boldness,
            preferredFit: preferredFit,
            temperatureSensitivity: TemperatureSensitivityOption(rawValue: temperatureSensitivityRawValue) ?? .balanced,
            statementPiecePreference: statementPiecePreference,
            rules: rules,
            updatedAt: updatedAt
        )
    }
}

private struct UserAvatarBackup: Codable {
    var id: UUID
    var sourcePhotoData: Data?
    var avatarImageData: Data?
    var latestPreviewData: Data?
    var latestPreviewCombinationKey: String
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case sourcePhotoData
        case avatarImageData
        case latestPreviewData
        case latestPreviewCombinationKey
        case notes
        case createdAt
        case updatedAt
    }

    init(avatar: UserAvatar) {
        id = avatar.id
        sourcePhotoData = avatar.sourcePhotoData
        avatarImageData = avatar.avatarImageData
        latestPreviewData = avatar.latestPreviewData
        latestPreviewCombinationKey = avatar.latestPreviewCombinationKey
        notes = avatar.notes
        createdAt = avatar.createdAt
        updatedAt = avatar.updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourcePhotoData = try container.decodeIfPresent(Data.self, forKey: .sourcePhotoData)
        avatarImageData = try container.decodeIfPresent(Data.self, forKey: .avatarImageData)
        latestPreviewData = try container.decodeIfPresent(Data.self, forKey: .latestPreviewData)
        latestPreviewCombinationKey = try container.decodeIfPresent(String.self, forKey: .latestPreviewCombinationKey) ?? ""
        notes = try container.decode(String.self, forKey: .notes)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    var model: UserAvatar {
        UserAvatar(
            id: id,
            sourcePhotoData: sourcePhotoData,
            avatarImageData: avatarImageData,
            latestPreviewData: latestPreviewData,
            latestPreviewCombinationKey: latestPreviewCombinationKey,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

private struct TripBackup: Codable {
    var id: UUID
    var title: String
    var startsAt: Date
    var endsAt: Date
    var notes: String
    var laundryIntervalDays: Int
    var wearsBeforeWash: Int
    var topWearsBeforeWash: Int
    var bottomWearsBeforeWash: Int
    var sweaterWearsBeforeWash: Int
    var jacketWearsBeforeWash: Int
    var activewearWearsBeforeWash: Int

    init(trip: Trip) {
        id = trip.id
        title = trip.title
        startsAt = trip.startsAt
        endsAt = trip.endsAt
        notes = trip.notes
        laundryIntervalDays = trip.laundryIntervalDays
        wearsBeforeWash = trip.wearsBeforeWash
        topWearsBeforeWash = trip.topWearsBeforeWash
        bottomWearsBeforeWash = trip.bottomWearsBeforeWash
        sweaterWearsBeforeWash = trip.sweaterWearsBeforeWash
        jacketWearsBeforeWash = trip.jacketWearsBeforeWash
        activewearWearsBeforeWash = trip.activewearWearsBeforeWash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        laundryIntervalDays = try container.decodeIfPresent(Int.self, forKey: .laundryIntervalDays) ?? 0
        wearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .wearsBeforeWash) ?? 1
        topWearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .topWearsBeforeWash) ?? max(1, wearsBeforeWash)
        bottomWearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .bottomWearsBeforeWash) ?? 3
        sweaterWearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .sweaterWearsBeforeWash) ?? 3
        jacketWearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .jacketWearsBeforeWash) ?? 5
        activewearWearsBeforeWash = try container.decodeIfPresent(Int.self, forKey: .activewearWearsBeforeWash) ?? 1
    }

    var model: Trip {
        Trip(
            id: id,
            title: title,
            startsAt: startsAt,
            endsAt: endsAt,
            notes: notes,
            laundryIntervalDays: laundryIntervalDays,
            wearsBeforeWash: max(1, wearsBeforeWash),
            topWearsBeforeWash: max(1, topWearsBeforeWash),
            bottomWearsBeforeWash: max(1, bottomWearsBeforeWash),
            sweaterWearsBeforeWash: max(1, sweaterWearsBeforeWash),
            jacketWearsBeforeWash: max(1, jacketWearsBeforeWash),
            activewearWearsBeforeWash: max(1, activewearWearsBeforeWash)
        )
    }
}

private struct TripStopBackup: Codable {
    var id: UUID
    var location: String
    var startsAt: Date
    var endsAt: Date
    var expectedWeather: String
    var customsNotes: String
    var requestedContextRawValues: String
    var isDailyPlanEntry: Bool
    var tripID: UUID

    private enum CodingKeys: String, CodingKey {
        case id
        case location
        case startsAt
        case endsAt
        case expectedWeather
        case customsNotes
        case requestedContextRawValues
        case isDailyPlanEntry
        case tripID
    }

    init(stop: TripStop) {
        id = stop.id
        location = stop.location
        startsAt = stop.startsAt
        endsAt = stop.endsAt
        expectedWeather = stop.expectedWeather
        customsNotes = stop.customsNotes
        requestedContextRawValues = stop.requestedContextRawValues
        isDailyPlanEntry = stop.isDailyPlanEntry
        tripID = stop.trip?.id ?? UUID()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        location = try container.decode(String.self, forKey: .location)
        startsAt = try container.decode(Date.self, forKey: .startsAt)
        endsAt = try container.decode(Date.self, forKey: .endsAt)
        expectedWeather = try container.decode(String.self, forKey: .expectedWeather)
        customsNotes = try container.decode(String.self, forKey: .customsNotes)
        requestedContextRawValues = try container.decodeIfPresent(String.self, forKey: .requestedContextRawValues) ?? ""
        isDailyPlanEntry = try container.decodeIfPresent(Bool.self, forKey: .isDailyPlanEntry) ?? false
        tripID = try container.decode(UUID.self, forKey: .tripID)
    }

    func model(trip: Trip) -> TripStop {
        TripStop(
            id: id,
            location: location,
            startsAt: startsAt,
            endsAt: endsAt,
            expectedWeather: expectedWeather,
            customsNotes: customsNotes,
            requestedContextRawValues: requestedContextRawValues,
            isDailyPlanEntry: isDailyPlanEntry,
            trip: trip
        )
    }
}

private struct PackingListBackup: Codable {
    var id: UUID
    var title: String
    var createdAt: Date
    var tripID: UUID

    init(list: PackingList) {
        id = list.id
        title = list.title
        createdAt = list.createdAt
        tripID = list.trip?.id ?? UUID()
    }

    func model(trip: Trip) -> PackingList {
        PackingList(id: id, title: title, createdAt: createdAt, trip: trip)
    }
}

private struct PackingListItemBackup: Codable {
    var id: UUID
    var quantity: Int
    var reason: String
    var itemID: UUID?
    var packingListID: UUID

    init(item: PackingListItem) {
        id = item.id
        quantity = item.quantity
        reason = item.reason
        itemID = item.item?.id
        packingListID = item.packingList?.id ?? UUID()
    }

    func model(clothingItem: ClothingItem?, packingList: PackingList) -> PackingListItem {
        PackingListItem(
            id: id,
            quantity: quantity,
            reason: reason,
            item: clothingItem,
            packingList: packingList
        )
    }
}

private struct DailyItineraryOutfitBackup: Codable {
    var id: UUID
    var date: Date
    var location: String
    var activity: String
    var tripID: UUID
    var outfitID: UUID?

    init(itinerary: DailyItineraryOutfit) {
        id = itinerary.id
        date = itinerary.date
        location = itinerary.location
        activity = itinerary.activity
        tripID = itinerary.trip?.id ?? UUID()
        outfitID = itinerary.outfit?.id
    }

    func model(trip: Trip, outfit: Outfit?) -> DailyItineraryOutfit {
        DailyItineraryOutfit(id: id, date: date, location: location, activity: activity, trip: trip, outfit: outfit)
    }
}
