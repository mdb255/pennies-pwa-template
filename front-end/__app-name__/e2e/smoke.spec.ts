import { test, expect } from '@playwright/test'

test('unauthenticated user sees the login screen', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByText('Log In')).toBeVisible()
})
