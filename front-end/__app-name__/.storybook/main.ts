import type { StorybookConfig } from '@storybook/react-vite'
import type { PluginOption } from 'vite'

const isPwaPlugin = (plugin: PluginOption): boolean =>
    Array.isArray(plugin)
        ? plugin.some(isPwaPlugin)
        : !!plugin && typeof plugin === 'object' && 'name' in plugin && plugin.name.startsWith('vite-plugin-pwa')

const config: StorybookConfig = {
    stories: ['../src/**/*.stories.@(ts|tsx)'],
    framework: {
        name: '@storybook/react-vite',
        options: {},
    },
    // Storybook inherits vite.config.ts; drop the PWA plugin, which has no use here and
    // fails the build on Storybook's large precache assets.
    viteFinal: (viteConfig) => ({
        ...viteConfig,
        plugins: (viteConfig.plugins ?? []).filter((plugin) => !isPwaPlugin(plugin)),
    }),
}

export default config
