import { json, error } from "@sveltejs/kit";
import type { RequestHandler } from "./$types";
import { getDashboardData, editOrCreateNote } from "$lib/server/queries";

export const GET: RequestHandler = async (event) => {
    if (!event.locals.user) {
        error(401, 'Unauthorized');
    }

    const data = await getDashboardData(event.locals.user.id);

    return json({ user: event.locals.user, ...data });
};

export const POST: RequestHandler = async (event) => {
    if (!event.locals.user) {
        error(401, 'Unauthorized');
    }

    const body = await event.request.json().catch(() => null);

    if (!body || typeof body.text !== 'string' || !body.text.trim()) {
        error(400, 'text is required');
    }

    try {
        await editOrCreateNote(event.locals.user.id, null, body.text, body.collaborators ? JSON.stringify(body.collaborators) : undefined, body.alerts ? JSON.stringify(body.alerts) : undefined);
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        error(500, message);
    }

    return new Response(null, { status: 201 });
};

export const PUT: RequestHandler = async (event) => {
    if (!event.locals.user) {
        error(401, 'Unauthorized');
    }

    const body = await event.request.json().catch(() => null);

    if (!body || typeof body.noteId !== 'string' || !body.noteId.trim()) {
        error(400, 'noteId is required');
    }

    if (typeof body.text !== 'string' || !body.text.trim()) {
        error(400, 'text is required');
    }

    try {
        await editOrCreateNote(event.locals.user.id, body.noteId, body.text, body.collaborators ? JSON.stringify(body.collaborators) : undefined, body.alerts ? JSON.stringify(body.alerts) : undefined);
    } catch (e) {
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Note not found') error(404, message);
        if (message === 'Forbidden') error(403, message);
        error(500, message);
    }

    return new Response(null, { status: 204 });
};
