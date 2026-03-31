import { Hono } from 'hono';
import { auth } from '../auth.js';

const token = new Hono();

token.post('/', async (c) => {
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.email !== 'string' || typeof body.password !== 'string') {
        return c.json({ error: 'email and password are required' }, 400);
    }

    const result = await auth.api.signInEmail({
        body: { email: body.email, password: body.password },
        returnHeaders: true,
    }).catch(() => null);

    if (!result) {
        return c.json({ error: 'Invalid credentials' }, 401);
    }

    const bearerToken = result.headers.get('set-auth-token');
    if (!bearerToken) {
        return c.json({ error: 'Failed to issue token' }, 500);
    }

    return c.json({ token: bearerToken });
});

export default token;
