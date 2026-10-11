import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
    testDir: './e2e',
    fullyParallel: true,
    reporter: 'html',
    use: {
        baseURL: 'http://localhost:<{{ dev_fe_port }}>',
        trace: 'on-first-retry',
    },
    projects: [
        { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    ],
    webServer: {
        command: 'pnpm run dev',
        url: 'http://localhost:<{{ dev_fe_port }}>',
        reuseExistingServer: !process.env.CI,
    },
})
