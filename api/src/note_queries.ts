import { db } from './db/index.js';
import { note, collaborator, noteHistory, noteOrder, noteFiles } from './db/schema.js';
import { eq, and, desc, notInArray, gte, sql } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { mkdir, rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { noteDirPath, noteFilePath } from './utils.js';

type Tx = Parameters<Parameters<(typeof db)['transaction']>[0]>[0];
type UploadedFile = { id: string; name: string; type: string; size: number };

export async function editOrCreateNote(
    userId: string,
    noteId: string | null,
    text: string,
    collaboratorsJson?: string,
    fixedPosition?: number,
    color?: string | null,
    files?: { name: string; type: string; size: number; stream: ReadableStream<Uint8Array> }[],
) {
    const isEdit = typeof noteId === 'string' && noteId.length > 0;

    // Pre-parse JSON before the transaction to fail fast on bad input
    const collabs = collaboratorsJson
        ? (JSON.parse(collaboratorsJson) as { userId: string; right: 'view' | 'edit' }[])
        : [];

    // Generate the note ID upfront so it can be used for both the upload
    // directory and the DB insert.
    const targetNoteId = isEdit ? (noteId as string) : randomUUID();

    // Upload files to disk before the transaction so we don't hold the DB
    // connection open during slow I/O. If the transaction later fails we clean up.
    const { uploadedFiles } = await uploadFiles(targetNoteId, files);

    try {
        await db.transaction(async (tx) => {

            if (isEdit) {
                const existing = await assertEditAccess(tx, targetNoteId, userId);
                await saveNoteBackup(tx, targetNoteId, existing.text);

                await tx
                    .update(note)
                    .set({ text: text.trim(), color: color ?? null })
                    .where(eq(note.id, targetNoteId));

                await tx.delete(collaborator).where(eq(collaborator.noteId, targetNoteId));
            } else {
                await tx
                    .insert(note)
                    .values({ id: targetNoteId, text: text.trim(), color: color ?? null, owner: userId });
            }

            if (collabs.length > 0) {
                await tx.insert(collaborator).values(
                    collabs.map((c) => ({ noteId: targetNoteId, userId: c.userId, right: c.right })),
                );
            }

            if (fixedPosition !== undefined) {
                // Shift all existing positions >= fixedPosition upward by 1 to make room,
                // excluding the note being saved (relevant in edit mode).
                await tx
                    .update(noteOrder)
                    .set({ position: sql`${noteOrder.position} + 1` })
                    .where(
                        and(
                            eq(noteOrder.userId, userId),
                            gte(noteOrder.position, fixedPosition),
                            ...(isEdit ? [sql`${noteOrder.noteId} != ${targetNoteId}`] : []),
                        ),
                    );

                await tx
                    .insert(noteOrder)
                    .values({ userId, noteId: targetNoteId, position: fixedPosition })
                    .onConflictDoUpdate({
                        target: [noteOrder.userId, noteOrder.noteId],
                        set: { position: fixedPosition },
                    });
            } else {
                await tx
                    .delete(noteOrder)
                    .where(and(eq(noteOrder.userId, userId), eq(noteOrder.noteId, targetNoteId)));
            }

            if (uploadedFiles.length > 0) {
                await tx.insert(noteFiles).values(
                    uploadedFiles.map((f) => ({
                        id: f.id,
                        noteId: targetNoteId,
                        fileName: f.name,
                        fileType: f.type,
                        fileSize: f.size,
                    })),
                );
            }
        });
    } catch (e) {
        // Transaction failed — remove any files we already wrote to disk.
        if (uploadedFiles.length > 0) {
            await Promise.allSettled(
                uploadedFiles.map((f) => rm(noteFilePath(targetNoteId, f.id), { force: true })),
            );
        }
        throw e;
    }
}

export async function deleteNote(userId: string, noteId: string): Promise<void> {
    const [existing] = await db
        .select({ id: note.id, owner: note.owner })
        .from(note)
        .where(eq(note.id, noteId));

    if (!existing) throw new Error('Note not found');
    if (existing.owner !== userId) throw new Error('Forbidden');

    const files = await db
        .select({ id: noteFiles.id })
        .from(noteFiles)
        .where(eq(noteFiles.noteId, noteId));

    await db.delete(note).where(eq(note.id, noteId));

    if (files.length > 0) {
        await rm(noteDirPath(noteId), { recursive: true, force: true });
    }
}

async function uploadFiles(
    noteId: string,
    files?: { name: string; type: string; size: number; stream: ReadableStream<Uint8Array> }[],
): Promise<{ uploadedFiles: UploadedFile[] }> {
    if (!files || files.length === 0) return { uploadedFiles: [] };

    const noteDir = noteDirPath(noteId);
    await mkdir(noteDir, { recursive: true });

    const uploadedFiles: UploadedFile[] = [];
    for (const file of files) {
        const id = randomUUID();
        await pipeline(
            Readable.fromWeb(file.stream as Parameters<typeof Readable.fromWeb>[0]),
            createWriteStream(noteFilePath(noteId, id)),
        );
        uploadedFiles.push({ id, name: file.name, type: file.type, size: file.size });
    }

    return { uploadedFiles };
}

async function assertEditAccess(
    tx: Tx,
    noteId: string,
    userId: string,
): Promise<{ id: string; owner: string; text: string }> {
    const [existing] = await tx
        .select({ id: note.id, owner: note.owner, text: note.text })
        .from(note)
        .where(eq(note.id, noteId));

    if (!existing) throw new Error('Note not found');

    const isOwner = existing.owner === userId;
    if (!isOwner) {
        const [collab] = await tx
            .select({ right: collaborator.right })
            .from(collaborator)
            .where(and(eq(collaborator.noteId, noteId), eq(collaborator.userId, userId)));
        if (!collab || collab.right !== 'edit') {
            throw new Error('Forbidden');
        }
    }

    return existing;
}

async function saveNoteBackup(tx: Tx, noteId: string, text: string): Promise<void> {
    await tx.insert(noteHistory).values({ noteId, text });

    const toKeep = await tx
        .select({ id: noteHistory.id })
        .from(noteHistory)
        .where(eq(noteHistory.noteId, noteId))
        .orderBy(desc(noteHistory.createdAt))
        .limit(10);

    await tx
        .delete(noteHistory)
        .where(and(
            eq(noteHistory.noteId, noteId),
            notInArray(noteHistory.id, toKeep.map((r) => r.id)),
        ));
}
