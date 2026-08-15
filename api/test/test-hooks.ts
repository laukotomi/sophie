import { beforeEach, beforeAll, afterAll } from 'vitest';
import { resetDatabase, ensureTestEnv, stopTestEnv } from './harness.js';

beforeAll(async () => {
    await ensureTestEnv();
});

beforeEach(async () => {
    await resetDatabase();
});

afterAll(async () => {
    await stopTestEnv();
});