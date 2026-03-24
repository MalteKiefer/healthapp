import { test, expect } from '@playwright/test';

test.describe('Navigation', () => {
  // These tests verify the app structure loads correctly
  // They don't require a running backend

  test('share view handles missing fragment', async ({ page }) => {
    await page.goto('/share/test123');
    // Should show an error about missing decryption key
    await expect(
      page.getByText(/no decryption key|share not found|loading/i)
    ).toBeVisible({ timeout: 5000 });
  });

  test('login page has correct title', async ({ page }) => {
    await page.goto('/login');
    await expect(page).toHaveTitle('HealthVault');
  });

  test('PWA manifest is accessible', async ({ page }) => {
    const response = await page.goto('/manifest.json');
    expect(response?.status()).toBe(200);
    const manifest = await response?.json();
    expect(manifest.name).toBe('HealthVault');
    expect(manifest.display).toBe('standalone');
  });
});
