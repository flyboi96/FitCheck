# FitCheck AI Proxy

Small local backend for FitCheck AI outfit review, AI-first outfit selection, clothing photo import, and avatar outfit previews. The iPhone app never stores the OpenAI API key; it calls this proxy instead.

## Run locally

1. Copy `backend/.env.example` to `backend/.env`.
2. Put your OpenAI API key in `OPENAI_API_KEY`.
3. Optional but recommended: set `FITCHECK_PROXY_TOKEN`.
4. Optional: set `OPENAI_VISION_MODEL` if you want clothing photo import to use a different model than outfit review.
5. Optional: set `OPENAI_IMAGE_MODEL` for avatar/outfit image previews. The default is `gpt-image-1`.
6. Optional: set `OPENAI_IMAGE_QUALITY=low` for faster draft avatar previews, or keep `medium` for better detail.
7. Run:

```sh
cd backend
set -a
source .env
set +a
node server.mjs
```

In FitCheck Settings:

- Turn on `Use AI proxy`.
- Set `Proxy endpoint` to the base URL, such as `http://127.0.0.1:8787` for the iOS Simulator. Do not include a route like `/outfit-recommendation`.
- Set `Proxy token` to the same value as `FITCHECK_PROXY_TOKEN`.

If the app says a route was not found, restart this backend from the latest code and confirm the base URL in Settings.

For a physical iPhone, set `HOST=0.0.0.0` before starting the proxy and use your Mac's LAN address instead of `127.0.0.1`.

## Render deployment

Use Render for the backend/API proxy only. GitHub Pages hosts the PWA frontend.

On Render, configure environment variables:

```text
OPENAI_API_KEY=...
FITCHECK_PROXY_TOKEN=...
HOST=0.0.0.0
PORT=8787
```

Use the Render service URL as `VITE_FITCHECK_PROXY_URL` in the GitHub Pages build secrets. The value should be the base URL only, such as:

```text
https://your-fitcheck-api.onrender.com
```

Do not add `/outfit-recommendation` or any other route to that URL.

## Routes

- `POST /outfit-recommendation` reviews a locally generated outfit or chooses an outfit from the closet when no candidate item IDs are supplied.
- `POST /clothing-item-description` accepts a compressed base64 image plus optional user notes and returns an editable clothing-item draft.
- `POST /style-profile-draft` turns guided style answers into editable style-preference fields.
- `POST /avatar-outfit-preview` accepts a compressed user reference photo plus outfit, weather, location, and style context, then returns a base64 PNG preview.
