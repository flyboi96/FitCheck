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

The profile document currently stores:

```text
displayName
gender
styleDescription
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
