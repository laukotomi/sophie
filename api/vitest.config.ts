import { defineConfig } from 'vitest/config';

export default defineConfig({
    test: {
        include: ['test/**/*.test.ts'],
        environment: 'node',
        testTimeout: 120_000,
        hookTimeout: 120_000,
        fileParallelism: false,
        globalSetup: ['./test/global-setup.ts'],
        setupFiles: ['./test/test-hooks.ts'],
        coverage: {
            provider: 'v8',
            reporter: ['text', 'html'],
        },
    },
});
