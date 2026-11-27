import { defineConfig, devices } from '@playwright/test';

// Browser tests for the website: the built site against a fake Supabase (tests/e2e/backend.ts).
// Run `npm run build:netlify` first, then `npm run test:e2e`.
export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  reporter: process.env.CI ? [['github'], ['list']] : 'list',
  use: { baseURL: 'http://127.0.0.1:4173', trace: 'off', ...devices['iPhone 13'], browserName: 'chromium' },
  webServer: { command: 'node tests/e2e/serve.mjs', url: 'http://127.0.0.1:4173', reuseExistingServer: !process.env.CI },
});
