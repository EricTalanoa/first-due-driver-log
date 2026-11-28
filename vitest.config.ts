import { defineConfig } from 'vitest/config';

// Logic tests for lib/.
export default defineConfig({ test: { include: ['tests/unit/**/*.test.ts'], environment: 'node' } });
