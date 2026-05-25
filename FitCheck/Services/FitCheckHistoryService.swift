import Foundation
import SwiftData

@MainActor
struct FitCheckHistoryService {
    func deleteOutfit(_ outfit: Outfit, context: ModelContext) throws {
        let outfitID = outfit.id

        for log in try context.fetch(FetchDescriptor<WearLog>()) where log.outfit?.id == outfitID {
            context.delete(log)
        }

        for entry in try context.fetch(FetchDescriptor<Feedback>()) where entry.outfit?.id == outfitID {
            context.delete(entry)
        }

        context.delete(outfit)
        try recalculateItemWearHistory(context: context)
        try context.save()
    }

    func deleteFeedback(_ feedback: Feedback, context: ModelContext) throws {
        context.delete(feedback)
        try context.save()
    }

    func clearLoggedHistory(context: ModelContext) throws {
        let now = Date()

        for log in try context.fetch(FetchDescriptor<WearLog>()) where log.date <= now {
            context.delete(log)
        }

        for outfit in try context.fetch(FetchDescriptor<Outfit>()) {
            guard let wornAt = outfit.wornAt, wornAt <= now else { continue }
            for entry in outfit.feedback {
                context.delete(entry)
            }
            context.delete(outfit)
        }

        try recalculateItemWearHistory(context: context)
        try context.save()
    }

    func recalculateItemWearHistory(context: ModelContext) throws {
        let logs = try context.fetch(FetchDescriptor<WearLog>())

        for item in try context.fetch(FetchDescriptor<ClothingItem>()) {
            let itemLogs = logs.filter { $0.item?.id == item.id }
            item.wearCount = itemLogs.count
            item.lastWornAt = itemLogs.map(\.date).max()
            item.updatedAt = Date()
        }
    }
}
