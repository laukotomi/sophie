import { fail, redirect } from "@sveltejs/kit";
import type { PageServerLoad, Actions } from "./$types";
import { eq, and } from "drizzle-orm";
import { db } from "$lib/server/db";
import { note, collaborator, alert as alertTable } from "$lib/server/db/schema";
import { editOrCreateNote, getDashboardData } from "$lib/server/queries";

export const load: PageServerLoad = async (event) => {
    if (!event.locals.user) {
        return redirect(302, '/auth');
    }

    const data = await getDashboardData(event.locals.user.id);

    return { user: event.locals.user, ...data };
};

export const actions: Actions = {
    default: async (event) => {
        if (!event.locals.user) {
            return fail(401, { message: 'Unauthorized' });
        }

        const formData = await event.request.formData();
        const text = formData.get('text');
        const noteId = formData.get('noteId');
        const collaboratorsJson = formData.get('collaborators');
        const alertsJson = formData.get('alerts');

        if (!text || typeof text !== 'string' || !text.trim()) {
            return fail(400, { message: 'Text is required' });
        }

        try {
            await editOrCreateNote(event.locals.user.id, typeof noteId === 'string' ? noteId : null, text, typeof collaboratorsJson === 'string' ? collaboratorsJson : undefined, typeof alertsJson === 'string' ? alertsJson : undefined);
        } catch (e) {
            const message = e instanceof Error ? e.message : 'Unknown error';
            if (message === 'Note not found') return fail(404, { message });
            if (message === 'Forbidden') return fail(403, { message });
            return fail(500, { message: 'An unexpected error occurred' });
        }

        return { success: true };
    }
};
