import { Hono } from 'hono';
import { editOrCreateNote, deleteNote, acquireNoteLock, releaseNoteLock, refreshNoteLock } from '../note_queries.js';
import { requireAuth, type AuthVariables } from '../middleware.js';

async function parseNoteForm(form: FormData) {
    const text = form.get('text');
    if (typeof text !== 'string' || !text.trim()) return null;

    const noteId = form.get('noteId');
    const collaborators = form.get('collaborators');
    const fixedPositionRaw = form.get('fixedPosition');
    const fixedPosition = fixedPositionRaw !== null && fixedPositionRaw !== ''
        ? parseInt(fixedPositionRaw as string, 10)
        : undefined;
    const colorRaw = form.get('color');
    const color = typeof colorRaw === 'string' && colorRaw ? colorRaw : null;

    const fileEntries = form.getAll('files').filter((f): f is File => f instanceof File);
    const filesData = fileEntries.map((f) => ({
        name: f.name,
        type: f.type || 'application/octet-stream',
        size: f.size,
        stream: f.stream(),
    }));

    return {
        text,
        noteId: typeof noteId === 'string' && noteId.trim() ? noteId : null,
        collaborators: typeof collaborators === 'string' && collaborators ? collaborators : undefined,
        fixedPosition: fixedPosition !== undefined && !isNaN(fixedPosition) ? fixedPosition : undefined,
        color,
        files: filesData.length > 0 ? filesData : undefined,
    };
}

const notes = new Hono<{ Variables: AuthVariables }>();

notes.use(requireAuth);

notes.post('/', async (c) => {
    const user = c.get('user');
    const form = await c.req.formData().catch(() => null);
    if (!form) return c.json({ error: 'text is required' }, 400);

    const parsed = await parseNoteForm(form);
    if (!parsed) return c.json({ error: 'text is required' }, 400);

    try {
        await editOrCreateNote(user.id, null, parsed.text, parsed.collaborators, parsed.fixedPosition, parsed.color, parsed.files);
    } catch (e) {
        console.error('[POST /api/notes] editOrCreateNote failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 201 });
});

notes.put('/', async (c) => {
    const user = c.get('user');
    const form = await c.req.formData().catch(() => null);
    if (!form) return c.json({ error: 'noteId is required' }, 400);

    const noteIdRaw = form.get('noteId');
    if (typeof noteIdRaw !== 'string' || !noteIdRaw.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }

    const parsed = await parseNoteForm(form);
    if (!parsed) return c.json({ error: 'text is required' }, 400);

    try {
        await editOrCreateNote(user.id, noteIdRaw, parsed.text, parsed.collaborators, parsed.fixedPosition, parsed.color, parsed.files);
    } catch (e) {
        console.error('[PUT /api/notes] editOrCreateNote failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        if (message === 'Lock required') return c.json({ error: message }, 409);
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
        console.error('[DELETE /api/notes] deleteNote failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

notes.post('/edit', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }

    try {
        const result = await acquireNoteLock(user.id, body.noteId);
        return c.json(result, 200);
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        if (message.startsWith('Locked:')) {
            return c.json({ error: 'Note is being edited by another user', editingBy: message.slice(7) }, 423);
        }
        console.error('[POST /api/notes/edit] acquireNoteLock failed:', e);
        return c.json({ error: message }, 500);
    }
});

notes.delete('/edit', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }

    await releaseNoteLock(user.id, body.noteId);
    return new Response(null, { status: 204 });
});

notes.patch('/edit', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);
    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        return c.json({ error: 'noteId is required' }, 400);
    }

    try {
        await refreshNoteLock(user.id, body.noteId);
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Lock not held') return c.json({ error: message }, 409);
        console.error('[PATCH /api/notes/edit] refreshNoteLock failed:', e);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

export default notes;
