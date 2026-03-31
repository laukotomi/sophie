import { json, error } from "@sveltejs/kit";
import type { RequestEvent } from "@sveltejs/kit";
import { auth } from "$lib/server/auth";

export const POST = async (event: RequestEvent) => {
    const body = await event.request.json().catch(() => null);

    if (!body || typeof body.email !== 'string' || typeof body.password !== 'string') {
        error(400, 'email and password are required');
    }

    const result = await auth.api.signInEmail({
        body: { email: body.email, password: body.password },
        returnHeaders: true,
    }).catch(() => null);

    if (!result) {
        error(401, 'Invalid credentials');
    }

    const token = result.headers.get('set-auth-token');

    if (!token) {
        error(500, 'Failed to issue token');
    }

    return json({ token });
};
