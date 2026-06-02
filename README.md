# FitCheck

FitCheck is a personal wardrobe and outfit planning app. The repository contains the original SwiftUI iPhone app plus a Progressive Web App in `web/`.

## MVP Scope

- Local digital closet with active, archived, and laundry/unavailable states
- Add and edit clothing item metadata, including quantity and item photos
- Photo-based closet import with optional notes and AI-generated item drafts
- Bulk text import for quickly entering a starting wardrobe
- Today's outfit recommendations from the clothes stored on device
- Current weather lookup with Core Location and Open-Meteo, including humidity, plus a fallback location in Settings
- Build an outfit around a selected item
- Outfit wear history, wear counts, and feedback
- Deletable outfit history, grouped wear logs by item, and clear-history controls
- Personal style preferences
- Plans for travel or normal weeks, with stops, packing lists, socks/underwear estimates, laundry-aware packing, separate packing/itinerary export, itinerary scoring comments, and itinerary feedback
- Wearer profile setting for male/female/unset personalization context
- Firebase Auth account screen for registering, signing in, and saving a cloud user profile
- Firestore user profile document for name, gender, and style preferences, plus optional per-user closet metadata sync
- Settings for an optional AI proxy endpoint
- Optional AI outfit review and clothing photo description through a local backend proxy
- JSON export/import for moving local FitCheck data to a new phone

## Architecture Notes

The first version stores data locally with SwiftData and uses a rules-based recommendation engine. The scoring engine considers weather, a combined context picker, color palette harmony, inferred dressiness, rotation history, style preferences, positive and negative feedback, and required-item bonuses.

Weather lookup uses Open-Meteo directly from the app. No weather API key is required for this MVP. The app asks for location permission by default, falls back to the default city saved in Settings if permission is denied or location lookup fails, and also supports typing a city or place for manual weather lookup. Manual weather also supports humidity.

OpenAI integration is intentionally behind an app-owned backend/proxy abstraction in `FitCheck/Services/OpenAIOutfitClient.swift`. Do not put an OpenAI API key in the iPhone app. For local prototyping, keep the key in a backend environment variable such as `OPENAI_API_KEY`, run `backend/server.mjs`, and point the app at that backend from Settings. The proxy supports outfit review, AI-first outfit selection, and clothing photo import.

The local color scorer recognizes neutrals, accent colors, analogous colors, complementary contrast, classic menswear pairings, and pattern conflicts. This keeps the app useful when the AI proxy is off.

Settings includes a backup section. Export writes closet items, outfit history, feedback, style preferences, trips, packing lists, and itinerary feedback to JSON. Import restores that JSON and replaces the local FitCheck data on the device.

Firebase is used for optional login and profile sync. SwiftData remains the local closet database for this version. Firestore stores one document per signed-in user at `users/{uid}` with account email, display name, gender, and style preferences. The Account screen can also upload/download closet metadata in `users/{uid}/clothingItems/{itemId}`. Photos are intentionally not synced yet; Firebase Storage is a better fit for that later.

## Progressive Web App

The PWA lives in `web/` and is intended to avoid the seven-day iOS free provisioning limit.

Deployment split:

- GitHub Pages hosts the PWA frontend at `https://flyboi96.github.io/FitCheck/`.
- Render hosts the backend proxy so the OpenAI API key stays off the phone and out of browser code.
- Firebase is used for Auth, Firestore, and security rules only.

See `PWA_MIGRATION.md` and `web/README.md`.

## Firebase Setup

1. Create a Firebase project.
2. Add an iOS app with bundle ID `com.alexcorbin.personal.FitCheck`.
3. Download `GoogleService-Info.plist`.
4. Add that plist to the FitCheck app target in Xcode. The file is gitignored so local Firebase project details do not need to be committed.
5. Enable Email/Password under Firebase Authentication.
6. Create a Cloud Firestore database.
7. Publish rules equivalent to `firestore.rules` so users can only read and write their own `users/{uid}` document and nested user data. From this folder, `firebase deploy --only firestore:rules` will use `firebase.json`.
8. For the PWA, add `flyboi96.github.io` under Firebase Authentication authorized domains.

After setup, open More > Account in FitCheck to register or sign in. Saving the account profile writes to Firestore and also applies the same gender/style preferences locally for outfit recommendations. Use the Cloud Personalization section to upload or download closet metadata for that signed-in user.

## AI Proxy

See `backend/README.md`.

The backend reads `OPENAI_API_KEY` and optional `FITCHECK_PROXY_TOKEN` from environment variables. The app stores only the proxy URL and optional proxy token.

## Open In Xcode

Open `FitCheck.xcodeproj` in Xcode and run the `FitCheck` scheme on an iPhone simulator.

## TestFlight

See `TESTFLIGHT.md` for the archive, upload, and smoke-test checklist.
