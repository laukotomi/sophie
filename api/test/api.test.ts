import { describe, expect, it } from 'vitest';
import { request, requestJson } from './harness.js';

describe('API integration (in-process)', () => {
    it('returns health status', async () => {
        const res = await request('/healthz');
        const body = await res.json();

        expect(res.status).toBe(200);
        expect(body).toEqual({ status: 'ok' });
    });

    it('validates token input payload', async () => {
        const res = await requestJson('/api/token', {
            method: 'POST',
            body: { email: 'x@example.com' },
        });

        const body = await res.json();

        expect(res.status).toBe(400);
        expect(body).toEqual({ error: 'email and password are required' });
    });
});
