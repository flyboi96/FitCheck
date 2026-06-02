# FitCheck PWA Migration

The native iOS app remains the reference implementation. The PWA lives in `web/` and will be built in phases so the repository stays clean.

## Current Phase

### `pwa-02-auth-firestore`

Status: complete.

Included:

- React + TypeScript + Vite app in `web/`
- PWA plugin, manifest, service worker, and iPhone Home Screen metadata
- Firebase Web SDK setup through `web/.env.local`
- GitHub Pages deployment workflow for `web/dist`
- FitCheck app shell with Today, Plans, Closet, Build, and More
- Firebase Auth login/register/logout
- User profile document under `users/{uid}` with `displayName`, `gender`, and `styleDescription`
- Firestore read/write helpers
- Protected app shell for signed-in users
- GitHub Pages workflow updated to Node 24-compatible Actions majors

## Next Phases

### `pwa-03-closet`

- Closet list
- Search/filter by category
- Add/edit clothing item
- Quantity, brand, notes, status
- Firestore sync

### `pwa-04-today-build-ai`

- Today context/weather panel
- Ask AI First outfit generation through the existing backend proxy
- Local fit-quality display
- Outfit feedback

### `pwa-05-plans`

- Trip/week plan editor
- Daily outfit requests
- AI itinerary generation
- Packing list derived from itinerary
- Share/export text

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

Firestore rules are still deployed with:

```bash
firebase deploy --only firestore:rules
```

## iPhone Install

Open the GitHub Pages URL in Safari:

```text
Share -> Add to Home Screen
```

This avoids the seven-day free iOS provisioning limit because the app is installed as a web app, not sideloaded as a native binary.

## Important Security Rule

The PWA can use Firebase Web config because those values are not OpenAI secrets. Do not put `OPENAI_API_KEY` in `web/`. AI requests must continue to go through `backend/`.
