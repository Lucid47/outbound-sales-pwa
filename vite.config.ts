import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// https://vite.dev/config/
export default defineConfig({
  base: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg', 'favicon-64.png', 'apple-touch-icon.png', 'pwa-192.png', 'pwa-512.png'],
      manifest: {
        name: '소희야 가자',
        short_name: '소희야 가자',
        description: '고객리스트 import, 오늘 스케줄, 지도, 전화, 문자, 방문 로그를 관리하는 PWA',
        theme_color: '#162032',
        background_color: '#f5f7fb',
        display: 'standalone',
        orientation: 'portrait',
        scope: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
        start_url: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
        id: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
        lang: 'ko',
        categories: ['business', 'productivity'],
        icons: [
          {
            src: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/pwa-192.png' : '/pwa-192.png',
            sizes: '192x192',
            type: 'image/png',
            purpose: 'any',
          },
          {
            src: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/pwa-512.png' : '/pwa-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'any',
          },
          {
            src: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/pwa-512.png' : '/pwa-512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        globPatterns: ['**/*.{js,css,html,svg,png,ico,webmanifest}'],
      },
      devOptions: {
        enabled: true,
      },
    }),
  ],
})
