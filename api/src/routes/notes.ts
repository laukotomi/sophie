import { Hono } from 'hono';
import { editOrCreateNote, deleteNote } from '../note_queries.js';
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
