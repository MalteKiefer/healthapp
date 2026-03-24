import { test, expect } from '@playwright/test';

test.describe('Authentication', () => {
  test('login page loads', async ({ page }) => {
    await page.goto('/login');
    await expect(page.getByText('HealthVault')).toBeVisible();
    await expect(page.getByLabel('Email')).toBeVisible();
    await expect(page.getByLabel('Passphrase')).toBeVisible();
  });

  test('login with invalid credentials shows error', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill('test@example.com');
    await page.getByLabel('Passphrase').fill('wrongpassword');
    await page.getByRole('button', { name: /log in/i }).click();

    // Should show an error (either connection error or invalid_credentials)
    await expect(page.getByRole('alert').or(page.getByText(/error|invalid/i))).toBeVisible({ timeout: 5000 });
  });

  test('unauthenticated user redirected to login', async ({ page }) => {
    await page.goto('/vitals');
    await expect(page).toHaveURL(/\/login/);
  });

  test('onboarding page loads', async ({ page }) => {
    await page.goto('/onboarding');
    await expect(page.getByText('Welcome to HealthVault')).toBeVisible();
  });

  test('404 page shows for unknown routes', async ({ page }) => {
    await page.goto('/nonexistent-page');
    await expect(page.getByText('404')).toBeVisible();
    await expect(page.getByText('Page not found')).toBeVisible();
  });
});
