/// <reference types="vitest/config" />
import { VitePWA } from 'vite-plugin-pwa';
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

// https://vitejs.dev/config/
export default defineConfig({
    // Mimics the prod CloudFront split: '/auth/*' is same-origin with the PWA and proxied to
    // the local backend, so authApi's session cookie is first-party. Data calls go straight to
    // VITE_API_BASE (cross-origin, Bearer) and are not proxied.
    server: {
        proxy: {
            '/auth': 'http://localhost:8000',
        },
    },
    plugins: [react(), tailwindcss(), VitePWA({
        registerType: 'prompt',
        injectRegister: false,

        pwaAssets: {
            disabled: false,
            config: true,
        },

        manifest: {
            name: '<{{ app_name }}>',
            short_name: '<{{ app_name }}>',
            description: '<{{ app_name }}>',
            theme_color: '#6d0fab',
            background_color: '#6d0fab',
        },

        workbox: {
            globPatterns: ['**/*.{js,css,html,svg,png,ico}'],
            cleanupOutdatedCaches: true,
            clientsClaim: true,
        },

        devOptions: {
            enabled: false,
            navigateFallback: 'index.html',
            suppressWarnings: true,
            type: 'module',
        },
    })],
    test: {
        environment: 'jsdom',
        globals: true,
        setupFiles: ['./src/test-setup.ts'],
    },
})