import { Hono } from 'hono';
import type { Session, User } from 'better-auth';
import { auth } from '../auth.js';
import { getDashboardData, editOrCreateNote, deleteNote } from '../queries.js';

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
    const form = await c.req.formData().catch(() => null);

    const text = form?.get('text');
    if (!form || typeof text !== 'string' || !text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    const collaborators = form.get('collaborators');
    const fixedPositionRaw = form.get('fixedPosition');
    const fixedPosition = fixedPositionRaw !== null && fixedPositionRaw !== ''
        ? parseInt(fixedPositionRaw as string, 10)
        : undefined;

    const fileEntries = form.getAll('files').filter((f): f is File => f instanceof File);
    const filesData = fileEntries.map((f) => ({
        name: f.name,
        type: f.type || 'application/octet-stream',
        size: f.size,
        stream: f.stream(),
    }));

    try {
        await editOrCreateNote(
            user.id,
            null,
            text,
            typeof collaborators === 'string' && collaborators ? collaborators : undefined,
            fixedPosition !== undefined && !isNaN(fixedPosition) ? fixedPosition : undefined,
            filesData.length > 0 ? filesData : undefined,
        );
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 201 });
});

notes.put('/', async (c) => {
    const user = c.get('user');
    const form = await c.req.formData().catch(() => null);

    const noteId = form?.get('noteId');
    if (!form || typeof noteId !== 'string' || !noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }
    const text = form.get('text');
    if (typeof text !== 'string' || !text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    const collaborators = form.get('collaborators');
    const fixedPositionRaw = form.get('fixedPosition');
    const fixedPosition = fixedPositionRaw !== null && fixedPositionRaw !== ''
        ? parseInt(fixedPositionRaw as string, 10)
        : undefined;

    const fileEntries = form.getAll('files').filter((f): f is File => f instanceof File);
    const filesData = fileEntries.map((f) => ({
        name: f.name,
        type: f.type || 'application/octet-stream',
        size: f.size,
        stream: f.stream(),
    }));

    try {
        await editOrCreateNote(
            user.id,
            noteId,
            text,
            typeof collaborators === 'string' && collaborators ? collaborators : undefined,
            fixedPosition !== undefined && !isNaN(fixedPosition) ? fixedPosition : undefined,
            filesData.length > 0 ? filesData : undefined,
        );
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

notes.delete('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }

    try {
        await deleteNote(user.id, body.noteId);
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

export default notes;
