# FitCheck Web PWA

This is the Progressive Web App version of FitCheck. It lives beside the native iOS app and will be ported in phases.

## Current Scope

- React + TypeScript + Vite scaffold
- PWA manifest and service worker setup
- iPhone Home Screen metadata
- Firebase Web SDK configuration
- GitHub Pages deployment workflow
- FitCheck app shell with the same primary sections as the iOS app
- Firebase Auth sign in, registration, password visibility toggle, and sign out
- Firestore user profile sync under `users/{uid}`
- Firestore closet sync under `users/{uid}/clothingItems`
- Closet search, category/status filters, add/edit, archive, delete, quantity, brand, notes
- Today and Build outfit generation from the active closet
- Manual weather/context inputs for outfit scoring
- Ask AI First through the Render backend proxy
- Outfit feedback saved under `users/{uid}/outfitFeedback`
- Plans saved under `users/{uid}/plans`
- Daily outfit requests, AI/local itinerary generation, derived packing list, and share text
- Weather lookup by city/current location through Open-Meteo
- Closet photo import through the backend proxy
- Avatar outfit previews through the backend proxy
- Outfit history, item wear logs, delete/clear history, and rotation stats
- Rich style profile fields plus AI Style Coach
- Saved avatar studio for reusable outfit previews
- JSON backup/export/import under More
- Scoring guide and editable context styles under More
- Reorderable plan days, editable generated itinerary cards, and editable packing list rows
- Firestore IndexedDB persistence for offline resilience
- More panels are lazy-loaded/code-split so backup, history, avatar, scoring, and context tools do not inflate the initial route
- Today, Plans, Closet, and Build are lazy-loaded/code-split by tab
- Vite manual chunks split React, Firebase, icons, and app feature code

The profile document currently stores:

```text
displayName
gender
styleDescription
favoriteLooks
preferredColors
preferredFit
temperatureSensitivity
statementPiecePreference
dislikedCombinations
rules
```

Each clothing item document currently stores:

```text
name
brand
category
categoryRawValue
quantity
color
pattern
notes
status
statusRawValue
wearCount
lastWornAt
createdAt
updatedAt
```

Each outfit feedback document currently stores:

```text
type
note
context
weatherSummary
itemIDs
itemNames
score
source
rationale
createdAt
```

Each logged outfit document under `users/{uid}/outfits` stores:

```text
name
context
contextLabel
wornAt
weatherSummary
itemIDs
itemNames
score
scoreLabel
source
rationale
note
createdAt
updatedAt
```

Each wear log document under `users/{uid}/wearLogs` stores:

```text
outfitID
outfitName
itemID
itemName
category
wornAt
context
note
createdAt
```

The saved avatar document under `users/{uid}/avatars/default` stores:

```text
imageBase64
mimeType
notes
updatedAt
```

The context styles document under `users/{uid}/contextStyles/default` stores:

```text
definitions
extraNotes
updatedAt
```

Each plan document currently stores:

```text
name
startDate
endDate
notes
days
itinerary
packingList
createdAt
updatedAt
```

## Local Setup

Create `web/.env.local` from `web/.env.example` and fill in the Firebase Web App config.

```bash
cd web
npm install
npm run dev
```

To test from an iPhone on the same Wi-Fi network:

```bash
cd web
npm run dev:host
```

Then open the LAN URL Vite prints in Safari.

## Build

```bash
cd web
npm run build
```

The production build is written to `web/dist`.

## GitHub Pages

The PWA is deployed from this repository to GitHub Pages:

```text
https://flyboi96.github.io/FitCheck/
```

The Vite `base` path is set to `/FitCheck/` because this is a project page, not a user-root page.

The deploy workflow is:

```text
.github/workflows/deploy-web.yml
```

The workflow uses Node 24-compatible GitHub Actions majors and sets:

```text
FORCE_JAVASCRIPT_ACTIONS_TO_NODE24=true
```

Before the first deploy, enable Pages in GitHub:

```text
Repository Settings -> Pages -> Build and deployment -> Source: GitHub Actions
```

Then add these repository secrets:

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

Set `VITE_FITCHECK_PROXY_URL` to the Render backend base URL. Do not include a route path.

Optional secret:

```text
VITE_FITCHECK_PROXY_TOKEN
```

For better flexibility, you can leave it blank in GitHub and enter the token on your device under `More -> Proxy Settings`.

The workflow runs automatically on pushes to `main`, or manually from:

```text
GitHub -> Actions -> Deploy FitCheck Web -> Run workflow
```

You can still build locally:

```bash
cd web
npm run build
```

After deployment, open the GitHub Pages URL in Safari and use:

```text
Share -> Add to Home Screen
```

## Firebase

Firebase is used for Auth and Firestore only. It does not host the page.

Add this GitHub Pages domain in Firebase Console:

```text
Authentication -> Settings -> Authorized domains -> flyboi96.github.io
```

## Backend Proxy

Do not put an OpenAI API key in this PWA. Keep using the existing `backend/` proxy for AI calls, deployed on Render.
The optional proxy token can gate your backend, but it is not a substitute for keeping the
OpenAI key server-side.

## Weather

The PWA uses Open-Meteo directly for weather lookup:

- City lookup uses `https://geocoding-api.open-meteo.com/v1/search`
- Forecast lookup uses `https://api.open-meteo.com/v1/forecast`

Open-Meteo does not require an API key for this use.
