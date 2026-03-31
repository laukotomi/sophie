import { Hono } from 'hono';
import type { Session, User } from 'better-auth';
import { auth } from '../auth.js';
import { getDashboardData, editOrCreateNote } from '../queries.js';

type Variables = { user: User; session: Session };

const notes = new Hono<{ Variables: Variables }>();

// Auth middleware — populates c.var.user for all routes in this router
notes.use(async (c, next) => {
    const session = await auth.api.getSession({ headers: c.req.raw.headers });
    if (!session) return c.json({ error: 'Unauthorized' }, 401);
    c.set('user', session.user);
    c.set('session', session.session);
    await next();
});

notes.get('/', async (c) => {
    const user = c.get('user');
    const data = await getDashboardData(user.id);
    return c.json({ user, ...data });
});

notes.post('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.text !== 'string' || !body.text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    try {
        await editOrCreateNote(
            user.id,
            null,
            body.text,
            body.collaborators ? JSON.stringify(body.collaborators) : undefined,
            body.alerts ? JSON.stringify(body.alerts) : undefined,
        );
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 201 });
});

notes.put('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }
    if (typeof body.text !== 'string' || !body.text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    try {
        await editOrCreateNote(
            user.id,
            body.noteId,
            body.text,
            body.collaborators ? JSON.stringify(body.collaborators) : undefined,
            body.alerts ? JSON.stringify(body.alerts) : undefined,
        );
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

export default notes;
