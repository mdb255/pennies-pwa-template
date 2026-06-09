import {
    defineConfig,
    minimal2023Preset,
} from '@vite-pwa/assets-generator/config'

export default defineConfig({
    headLinkOptions: {
        preset: '2023',
    },
    preset: {
        ...minimal2023Preset,
        maskable: {
            sizes: [192, 512],
            padding: 0.15, // Standard 15% padding for the safe zone
            resizeOptions: {
                background: '#6d0fab',
            }
        },
        apple: {
            sizes: [180, 192, 512],
            resizeOptions: {
                background: '#6d0fab',
            }
        },
    },
    images: ['public/favicon_v2.png'],
});
