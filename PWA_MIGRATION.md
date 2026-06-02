# FitCheck PWA Migration

The native iOS app remains the reference implementation. The PWA lives in `web/` and will be built in phases so the repository stays clean.

## Current Phase

### `pwa-07-portability-context-plan-offline`

Status: complete.

Included:

- React + TypeScript + Vite app in `web/`
- PWA plugin, manifest, service worker, and iPhone Home Screen metadata
- Firebase Web SDK setup through `web/.env.local`
- GitHub Pages deployment workflow for `web/dist`
- FitCheck app shell with Today, Plans, Closet, Build, and More
- Firebase Auth login/register/logout
- User profile document under `users/{uid}` with account, gender/profile, rich style preferences, temperature comfort, disliked combinations, and rules
- Firestore read/write helpers
- Protected app shell for signed-in users
- GitHub Pages workflow updated to Node 24-compatible Actions majors
- Closet list
- Search/filter by category
- Add/edit clothing item
- Quantity, brand, notes, status
- Firestore sync
- GitHub Pages artifact upload updated to `actions/upload-pages-artifact@v5`
- Today context/weather panel
- Build page for optional required item selection
- Local outfit scoring with 0-100 fit-quality display
- Ask AI First through the existing backend proxy
- Outfit feedback saved under `users/{uid}/outfitFeedback`
- Trip/week plan editor
- Daily outfit requests
- AI itinerary generation
- Packing list derived from itinerary
- Share/export text
- Weather lookup for Today and plan days using Open-Meteo
- Closet photo import in the PWA through the backend proxy
- Avatar outfit previews in the PWA through the backend proxy
- Outfit history under `users/{uid}/outfits`
- Item wear logs under `users/{uid}/wearLogs`
- Log Wear action from generated outfits
- Wear count and last-worn rotation stats on closet items
- Clear/delete outfit history controls
- AI Style Coach through the existing backend proxy
- Saved avatar reference/base image under `users/{uid}/avatars/default`
- Avatar Studio in More
- JSON backup/export/import for profile, closet, plans, history, feedback, avatar, and context metadata
- Scoring guide in More
- Editable context-style definitions under `users/{uid}/contextStyles/default`
- Context style definitions included in AI outfit requests
- Reorderable plan days
- Editable generated itinerary cards
- Direct packing-list name, quantity, and remove controls
- Clearer itinerary-to-packing-list flow
- Firestore IndexedDB offline persistence
- More panels are lazy-loaded/code-split to reduce initial PWA bundle size
- Today, Plans, Closet, and Build tabs are lazy-loaded/code-split
- Vite manual chunks split React, Firebase, icons, and app feature code

## Next Ideas

- Calendar import
- Weather fallback for dates outside forecast range
- PWA backup merge mode instead of replace-only import

## Hosting Setup

The PWA frontend is hosted on GitHub Pages:

```text
https://flyboi96.github.io/FitCheck/
```

The backend proxy remains on Render and is the only place that should hold `OPENAI_API_KEY`.

Firebase is used for Auth, Firestore, and rules only. It does not host the PWA page.
Open-Meteo is used directly from the PWA for city/current-location weather lookup and does not require an API key.

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

Prefer entering the token in the PWA under `More -> Proxy Settings` if you do not want it baked into the GitHub Pages build.

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
The optional proxy token is not an OpenAI key, but it is visible to browser code if included in the PWA build.
