# FitCheck

FitCheck is a personal wardrobe and outfit planning Progressive Web App. It stores a real digital closet, generates outfit recommendations from owned clothing, plans trip/week itineraries, tracks wear history, and uses a backend proxy for AI features without exposing the OpenAI API key in browser code.

The repository is now PWA-only. The original Swift app was archived before removal with:

```bash
git tag ios-swift-archive-before-pwa-cleanup
```

## Current Architecture

- `web/`: React, TypeScript, Vite, and PWA frontend hosted on GitHub Pages.
- `backend/`: Node backend proxy hosted on Render for OpenAI, avatar image generation, photo import, style coaching, and server-side weather fallback.
- `firestore.rules`: Firestore security rules for per-user data.
- `firebase.json`: Firebase CLI config for deploying Firestore rules.
- `.github/workflows/deploy-web.yml`: GitHub Pages deployment workflow.

Deployment split:

- GitHub Pages hosts the PWA at `https://flyboi96.github.io/FitCheck/`.
- Render hosts the backend proxy.
- Firebase handles Authentication and Firestore.
- OpenAI keys stay in Render environment variables only.

## App Features

- Firebase Auth login/register
- User profile with name, gender, style preferences, temperature comfort, disliked combinations, and personal rules
- Digital closet with search, category/status filters, brand, quantity, notes, archive/delete, and wear stats
- Bulk closet import for first-time wardrobe setup
- AI photo import for clothing item drafts
- Today and Build outfit generation
- Editable outfit contexts under More
- Local outfit scoring plus optional AI-first outfit selection
- Weather lookup by current location or city, with day-specific forecast lookup for plans
- Open-Meteo browser lookup with Render proxy fallback and MET Norway backend fallback
- Outfit feedback and wear history
- Trip/week plans with daily outfit requests, generated itineraries, packing lists, reorderable days, editable itinerary cards, and editable packing rows
- Avatar Studio and avatar outfit previews through the backend proxy
- JSON backup/export/import for profile, closet, plans, history, feedback, avatar metadata, and context settings
- Firestore IndexedDB persistence for weak-connection/offline resilience

## Local Setup

Frontend:

```bash
cd web
npm install
cp .env.example .env.local
npm run dev
```

Backend:

```bash
cd backend
npm install
cp .env.example .env
npm start
```

The backend `.env` should contain:

```text
OPENAI_API_KEY=...
FITCHECK_PROXY_TOKEN=...
HOST=0.0.0.0
PORT=8787
```

Never put `OPENAI_API_KEY` in `web/` or GitHub Pages secrets.

## GitHub Pages

The PWA deploys from `.github/workflows/deploy-web.yml`.

Required GitHub Actions secrets:

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

`VITE_FITCHECK_PROXY_URL` should be the Render backend base URL, for example:

```text
https://your-fitcheck-api.onrender.com
```

Optional:

```text
VITE_FITCHECK_PROXY_TOKEN
```

Prefer entering the proxy token in the PWA under `More -> AI Proxy` if you do not want it baked into the GitHub Pages build.

## Firebase

1. Enable Email/Password Authentication.
2. Add `flyboi96.github.io` as an authorized Firebase Auth domain.
3. Create a Cloud Firestore database.
4. Deploy rules:

```bash
firebase deploy --only firestore:rules
```

The PWA stores user data under `users/{uid}` and nested subcollections such as `clothingItems`, `plans`, `outfits`, `wearLogs`, `outfitFeedback`, `avatars`, and `contextStyles`.

## Backend Proxy

See `backend/README.md`.

Main routes:

- `GET /health`
- `POST /outfit-recommendation`
- `POST /clothing-item-description`
- `POST /style-profile-draft`
- `POST /avatar-outfit-preview`
- `POST /weather-lookup`

## Install On iPhone

Open the GitHub Pages URL in Safari:

```text
Share -> Add to Home Screen
```

This avoids the seven-day Apple free provisioning limit because FitCheck is installed as a PWA.
