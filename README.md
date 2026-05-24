# FitCheck

FitCheck is a personal iPhone wardrobe and outfit planning app built with SwiftUI and SwiftData.

## MVP Scope

- Local digital closet with active, archived, and laundry/unavailable states
- Add and edit clothing item metadata
- Today's outfit recommendations from the clothes stored on device
- Current weather lookup with Core Location and Open-Meteo, plus a fallback location in Settings
- Build an outfit around a selected item
- Outfit wear history, wear counts, and feedback
- Personal style preferences
- Trip stops, packing lists, and basic outfit itineraries
- Settings for an optional AI proxy endpoint

## Architecture Notes

The first version stores data locally with SwiftData and uses a rules-based recommendation engine. The scoring engine considers weather, occasion, activity, color compatibility, formality, rotation history, style preferences, negative feedback, and required-item bonuses.

Weather lookup uses Open-Meteo directly from the app. No weather API key is required for this MVP. The app asks for location permission and falls back to the coordinates saved in Settings if permission is denied or location lookup fails.

OpenAI integration is intentionally behind an app-owned backend/proxy abstraction in `FitCheck/Services/OpenAIOutfitClient.swift`. Do not put an OpenAI API key in the iPhone app. For local prototyping, keep the key in a backend environment variable such as `OPENAI_API_KEY` and point the app at that backend from Settings.

## Open In Xcode

Open `FitCheck.xcodeproj` in Xcode and run the `FitCheck` scheme on an iPhone simulator.
