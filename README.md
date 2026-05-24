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
- Optional AI outfit review through a local backend proxy

## Architecture Notes

The first version stores data locally with SwiftData and uses a rules-based recommendation engine. The scoring engine considers weather, occasion, activity, color palette harmony, inferred dressiness, rotation history, style preferences, negative feedback, and required-item bonuses.

Weather lookup uses Open-Meteo directly from the app. No weather API key is required for this MVP. The app asks for location permission by default, falls back to the default city saved in Settings if permission is denied or location lookup fails, and also supports typing a city or place for manual weather lookup.

OpenAI integration is intentionally behind an app-owned backend/proxy abstraction in `FitCheck/Services/OpenAIOutfitClient.swift`. Do not put an OpenAI API key in the iPhone app. For local prototyping, keep the key in a backend environment variable such as `OPENAI_API_KEY`, run `backend/server.mjs`, and point the app at that backend from Settings.

The local color scorer recognizes neutrals, accent colors, analogous colors, complementary contrast, classic menswear pairings, and pattern conflicts. This keeps the app useful when the AI proxy is off.

## AI Proxy

See `backend/README.md`.

The backend reads `OPENAI_API_KEY` and optional `FITCHECK_PROXY_TOKEN` from environment variables. The app stores only the proxy URL and optional proxy token.

## Open In Xcode

Open `FitCheck.xcodeproj` in Xcode and run the `FitCheck` scheme on an iPhone simulator.
