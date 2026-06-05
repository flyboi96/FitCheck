# FitCheck PWA Migration

The migration from native iOS to PWA is complete. The Swift app was archived in git history and removed from the active repository so future work can focus on one implementation.

Archive tag:

```bash
git tag ios-swift-archive-before-pwa-cleanup
```

## Current Status

FitCheck now runs as a Progressive Web App in `web/` with a Render-hosted backend proxy in `backend/`.

Completed PWA capabilities:

- React + TypeScript + Vite PWA shell
- GitHub Pages deploy workflow
- Firebase Auth and Firestore user data
- Closet add/edit/search/filter/archive/delete
- Quantity, brand, notes, status, wear count, and last-worn stats
- Bulk closet import
- Clothing photo import through backend AI proxy
- Today and Build outfit generation
- Editable context styles
- Local scorer plus optional AI-first outfit selection
- Weather lookup by city/current location with day-specific plan forecasts
- Backend weather fallback through Open-Meteo, MET Norway, and Nominatim geocoding
- Trip/week plans with daily requests, generated itinerary, generated packing list, reorderable days, editable itinerary cards, and editable packing rows
- Outfit feedback, history, wear logs, and clear/delete controls
- AI Style Coach
- Avatar Studio and avatar outfit previews
- JSON backup/export/import
- Firestore offline persistence
- Lazy-loaded tabs and More panels
- Manual Vite chunks for React, Firebase, icons, and feature code

## Hosting Setup

The PWA frontend is hosted on GitHub Pages:

```text
https://flyboi96.github.io/FitCheck/
```

The backend proxy remains on Render and is the only place that should hold `OPENAI_API_KEY`.

Firebase is used for Auth, Firestore, and rules only. It does not host the PWA page.

## GitHub Pages Setup

1. In GitHub, open `flyboi96/FitCheck`.
2. Go to:

```text
Settings -> Pages
```

3. Set:

```text
Build and deployment -> Source -> GitHub Actions
```

4. Add repository secrets:

```text
Settings -> Secrets and variables -> Actions -> New repository secret
```

Required secrets:

```text
VITE_FIREBASE_API_KEY
VITE_FIREBASE_AUTH_DOMAIN
VITE_FIREBASE_PROJECT_ID
VITE_FIREBASE_STORAGE_BUCKET
VITE_FIREBASE_MESSAGING_SENDER_ID
VITE_FIREBASE_APP_ID
VITE_FIREBASE_MEASUREMENT_ID
VITE_FITCHECK_PROXY_URL
```

Set `VITE_FITCHECK_PROXY_URL` to the Render backend base URL, for example:

```text
https://your-fitcheck-api.onrender.com
```

Optional secret:

```text
VITE_FITCHECK_PROXY_TOKEN
```

Prefer entering the token in the PWA under `More -> AI Proxy` if you do not want it baked into the GitHub Pages build.

5. Push to `main`, or run:

```text
Actions -> Deploy FitCheck Web -> Run workflow
```

## Firebase Auth Setup

Add the GitHub Pages host as an authorized Firebase Auth domain:

```text
Firebase Console -> Authentication -> Settings -> Authorized domains
```

Add:

```text
flyboi96.github.io
```

Firestore rules are deployed with:

```bash
firebase deploy --only firestore:rules
```

## iPhone Install

Open the GitHub Pages URL in Safari:

```text
Share -> Add to Home Screen
```

This avoids the seven-day free iOS provisioning limit because the app is installed as a web app, not sideloaded as a native binary.

## Security Rule

The PWA can use Firebase Web config because those values are not OpenAI secrets. Do not put `OPENAI_API_KEY` in `web/`. AI requests must continue to go through `backend/`.

The optional proxy token is not an OpenAI key, but it is visible to browser code if included in the PWA build.
