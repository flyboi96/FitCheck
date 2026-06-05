import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

const githubPagesBase = '/FitCheck/'
const appVersion = process.env.npm_package_version ?? '1.4.0'
const buildId = process.env.VITE_FITCHECK_BUILD_ID ?? process.env.GITHUB_SHA ?? 'local'

export default defineConfig({
  base: githubPagesBase,
  define: {
    'import.meta.env.VITE_FITCHECK_APP_VERSION': JSON.stringify(appVersion),
    'import.meta.env.VITE_FITCHECK_BUILD_ID': JSON.stringify(buildId),
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) {
            return undefined
          }

          if (id.includes('/react/') || id.includes('/react-dom/')) {
            return 'vendor-react'
          }

          if (
            id.includes('/firebase/') ||
            id.includes('/@firebase/') ||
            id.includes('/idb/')
          ) {
            return 'vendor-firebase'
          }

          if (id.includes('/lucide-react/')) {
            return 'vendor-icons'
          }

          if (id.includes('/workbox-') || id.includes('/vite-plugin-pwa/')) {
            return 'vendor-pwa'
          }

          return 'vendor'
        },
      },
    },
  },
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: 'FitCheck',
        short_name: 'FitCheck',
        description: 'Personal wardrobe, outfit planning, and trip packing.',
        theme_color: '#0a0b0d',
        background_color: '#0a0b0d',
        display: 'standalone',
        orientation: 'portrait',
        start_url: githubPagesBase,
        scope: githubPagesBase,
        icons: [
          {
            src: `${githubPagesBase}apple-touch-icon.png`,
            sizes: '180x180',
            type: 'image/png',
          },
          {
            src: `${githubPagesBase}pwa-1024.png`,
            sizes: '1024x1024',
            type: 'image/png',
            purpose: 'any maskable',
          },
        ],
      },
      workbox: {
        navigateFallback: `${githubPagesBase}index.html`,
      },
      devOptions: {
        enabled: true,
      },
    }),
  ],
})
