import { defineConfig } from 'vitest/config';

// Logic tests for lib/. Kept apart from vite.config.ts, which is the unused starter template's.
export default defineConfig({ test: { include: ['tests/unit/**/*.test.ts'], environment: 'node' } });
