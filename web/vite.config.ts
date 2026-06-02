import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

const githubPagesBase = '/FitCheck/'

export default defineConfig({
  base: githubPagesBase,
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
