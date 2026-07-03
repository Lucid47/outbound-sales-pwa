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
      includeAssets: ['favicon.svg', 'apple-touch-icon.svg'],
      manifest: {
        name: '아웃바운드 영업 도우미',
        short_name: '영업도우미',
        description: '고객리스트 import, 오늘 스케줄, 지도, 전화, 문자, 방문 로그를 관리하는 PWA',
        theme_color: '#162032',
        background_color: '#f5f7fb',
        display: 'standalone',
        orientation: 'portrait',
        scope: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
        start_url: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/' : '/',
        icons: [
          {
            src: process.env.DEPLOY_TARGET === 'github-pages' ? '/outbound-sales/pwa-icon.svg' : '/pwa-icon.svg',
            sizes: '512x512',
            type: 'image/svg+xml',
            purpose: 'any maskable',
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
