import { Hono } from 'hono';
import type { Session, User } from 'better-auth';
import { auth } from '../auth.js';
import { db } from '../db/index.js';
import { note, collaborator, noteFiles } from '../db/schema.js';
import { eq, and } from 'drizzle-orm';
import { createReadStream, unlink } from 'node:fs';
import { join } from 'node:path';

type Variables = { user: User; session: Session };

const files = new Hono<{ Variables: Variables }>();

// Auth middleware
files.use(async (c, next) => {
    const session = await auth.api.getSession({ headers: c.req.raw.headers });
    if (!session) return c.json({ error: 'Unauthorized' }, 401);
    c.set('user', session.user);
    c.set('session', session.session);
    await next();
});

type AccessLevel = 'any' | 'edit';

type FileRecord = { id: string; noteId: string; fileName: string; fileType: string };

async function resolveFileAccess(
    fileId: string,
    userId: string,
    required: AccessLevel,
): Promise<{ record: FileRecord; error: null } | { record: null; error: Response }> {
    const err = (body: { error: string }, status: 403 | 404) =>
        ({ record: null, error: Response.json(body, { status }) }) as const;

    const [record] = await db
        .select({ id: noteFiles.id, noteId: noteFiles.noteId, fileName: noteFiles.fileName, fileType: noteFiles.fileType })
        .from(noteFiles)
        .where(eq(noteFiles.id, fileId));

    if (!record) return err({ error: 'File not found' }, 404);

    const [noteRecord] = await db
        .select({ owner: note.owner })
        .from(note)
        .where(eq(note.id, record.noteId));

    if (!noteRecord) return err({ error: 'File not found' }, 404);

    if (noteRecord.owner !== userId) {
        const [collab] = await db
            .select({ right: collaborator.right })
            .from(collaborator)
            .where(and(eq(collaborator.noteId, record.noteId), eq(collaborator.userId, userId)));

        if (!collab) return err({ error: 'Forbidden' }, 403);
        if (required === 'edit' && collab.right !== 'edit') return err({ error: 'Forbidden' }, 403);
    }

    return { record, error: null };
}

files.get('/', async (c) => {
    const user = c.get('user');
    const fileId = c.req.query('id');

    if (!fileId?.trim()) {
        return c.json({ error: 'id query parameter is required' }, 400);
    }

    const { record, error } = await resolveFileAccess(fileId, user.id, 'any');
    if (error) return error;

    const uploadsDir = process.env.UPLOADS_DIR ?? './uploads';
    const filePath = join(uploadsDir, record.noteId, record.id);

    const readStream = createReadStream(filePath);

    const webStream = new ReadableStream({
        start(controller) {
            readStream.on('data', (chunk) => controller.enqueue(chunk));
            readStream.on('end', () => controller.close());
            readStream.on('error', (err) => {
                if ((err as NodeJS.ErrnoException).code === 'ENOENT') {
                    controller.error(Object.assign(new Error('File not found on disk'), { code: 'ENOENT' }));
                } else {
                    controller.error(err);
                }
            });
        },
        cancel() {
            readStream.destroy();
        },
    });

    return new Response(webStream, {
        headers: {
            'Content-Type': record.fileType,
            'Content-Disposition': `attachment; filename="${encodeURIComponent(record.fileName)}"`,
        },
    });
});

files.delete('/', async (c) => {
    const user = c.get('user');
    const fileId = c.req.query('id');

    if (!fileId?.trim()) {
        return c.json({ error: 'id query parameter is required' }, 400);
    }

    const { record, error } = await resolveFileAccess(fileId, user.id, 'edit');
    if (error) return error;

    await db.delete(noteFiles).where(eq(noteFiles.id, record.id));

    const uploadsDir = process.env.UPLOADS_DIR ?? './uploads';
    const filePath = join(uploadsDir, record.noteId, record.id);
    await new Promise<void>((resolve) => unlink(filePath, () => resolve()));

    return new Response(null, { status: 204 });
});

export default files;
