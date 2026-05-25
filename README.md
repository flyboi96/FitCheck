# FitCheck

FitCheck is a personal iPhone wardrobe and outfit planning app built with SwiftUI and SwiftData.

## MVP Scope

- Local digital closet with active, archived, and laundry/unavailable states
- Add and edit clothing item metadata, including item photos
- Photo-based closet import with optional notes and AI-generated item drafts
- Today's outfit recommendations from the clothes stored on device
- Current weather lookup with Core Location and Open-Meteo, plus a fallback location in Settings
- Build an outfit around a selected item
- Outfit wear history, wear counts, and feedback
- Deletable outfit history, grouped wear logs by item, and clear-history controls
- Personal style preferences
- Trip stops, packing lists, socks/underwear estimates, laundry-aware packing, itinerary feedback, and basic outfit itineraries
- Wearer profile setting for male/female/unset personalization context
- Settings for an optional AI proxy endpoint
- Optional AI outfit review and clothing photo description through a local backend proxy
- JSON export/import for moving local FitCheck data to a new phone

## Architecture Notes

The first version stores data locally with SwiftData and uses a rules-based recommendation engine. The scoring engine considers weather, a combined context picker, color palette harmony, inferred dressiness, rotation history, style preferences, positive and negative feedback, and required-item bonuses.

Weather lookup uses Open-Meteo directly from the app. No weather API key is required for this MVP. The app asks for location permission by default, falls back to the default city saved in Settings if permission is denied or location lookup fails, and also supports typing a city or place for manual weather lookup.

OpenAI integration is intentionally behind an app-owned backend/proxy abstraction in `FitCheck/Services/OpenAIOutfitClient.swift`. Do not put an OpenAI API key in the iPhone app. For local prototyping, keep the key in a backend environment variable such as `OPENAI_API_KEY`, run `backend/server.mjs`, and point the app at that backend from Settings. The proxy supports both outfit review and clothing photo import.

The local color scorer recognizes neutrals, accent colors, analogous colors, complementary contrast, classic menswear pairings, and pattern conflicts. This keeps the app useful when the AI proxy is off.

Settings includes a backup section. Export writes closet items, outfit history, feedback, style preferences, trips, packing lists, and itinerary feedback to JSON. Import restores that JSON and replaces the local FitCheck data on the device.

## AI Proxy

See `backend/README.md`.

The backend reads `OPENAI_API_KEY` and optional `FITCHECK_PROXY_TOKEN` from environment variables. The app stores only the proxy URL and optional proxy token.

## Open In Xcode

Open `FitCheck.xcodeproj` in Xcode and run the `FitCheck` scheme on an iPhone simulator.
