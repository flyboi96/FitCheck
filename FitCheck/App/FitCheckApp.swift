import SwiftData
import SwiftUI

@main
struct FitCheckApp: App {
    @UIApplicationDelegateAdaptor(FitCheckFirebaseAppDelegate.self) private var firebaseDelegate

    var body: some Scene {
        WindowGroup {
            FitCheckRootView()
        }
        .modelContainer(for: FitCheckApp.modelTypes)
    }

    private static var modelTypes: [any PersistentModel.Type] {
        [
            ClothingItem.self,
            Outfit.self,
            OutfitItemLink.self,
            WearLog.self,
            Feedback.self,
            StylePreference.self,
            Trip.self,
            TripStop.self,
            PackingList.self,
            PackingListItem.self,
            DailyItineraryOutfit.self
        ]
    }
}
