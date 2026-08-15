import { db } from './db/index.js';
import { note, collaborator, noteHistory, noteOrder, noteFiles } from './db/schema.js';
import { eq, and, or, isNull, lt, desc, notInArray, gte, sql } from 'drizzle-orm';
import { mkdir, rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { noteDirPath, noteFilePath } from './utils.js';
import { NoteFormData, UploadedFile } from './models.js';
import type { AnyPgColumn } from 'drizzle-orm/pg-core';

const noteHistoryLimit = 50;
const lockTimeoutMs = 60_000;

type Note = typeof note.$inferSelect;

type ExtraFieldColumns = {
    [K in keyof Note]?: AnyPgColumn<{ data: Note[K] }>;
};

type Tx = Parameters<Parameters<(typeof db)['transaction']>[0]>[0];

export async function upsertNote(
    userId: string,
    noteData: NoteFormData
) {
    console.log(`START upsertNote - userId: ${userId}, noteId: ${noteData.noteId}`);

    const existing = await assertEditAccessIfExists(noteData.noteId, userId, {
        lockedUntil: note.lockedUntil,
        editingBy: note.editingBy,
        text: note.text,
    });

    if (existing?.lockedUntil) {
        const lockTimeout = new Date(Date.now() + lockTimeoutMs);
        if (existing.lockedUntil < lockTimeout && existing.editingBy !== userId) {
            throw new Error('Lock required');
        }
    }

    // Upload files to disk before the transaction so we don't hold the DB
    // connection open during slow I/O. If the transaction later fails we clean up.
    const uploadedFiles = await uploadFiles(noteData.noteId, noteData.files);
    console.log(`Uploaded ${uploadedFiles.length} files`);

    const noteDbData = {
        text: noteData.text,
        color: noteData.color,
        dontFold: noteData.dontFold,
        todoList: noteData.todoList,
    }

    try {
        await db.transaction(async (tx) => {
            if (existing) {
                await saveNoteBackup(tx, noteData.noteId, existing.text);
            }

            await tx
                .insert(note)
                .values({
                    id: noteData.noteId,
                    createdAt: noteData.timestamp,
                    updatedAt: noteData.timestamp,
                    owner: userId,
                    ...noteDbData,
                })
                .onConflictDoUpdate({
                    target: [note.id],
                    set: {
                        editingBy: null,
                        lockedUntil: null,
                        updatedAt: noteData.timestamp,
                        ...noteDbData,
                    },
                });


            await tx.delete(collaborator).where(eq(collaborator.noteId, noteData.noteId));

            if (noteData.collaborators && noteData.collaborators.length > 0) {
                await tx.insert(collaborator).values(
                    noteData.collaborators.map((c) => ({ noteId: noteData.noteId, userId: c.userId, right: c.right })),
                );
            }

            if (noteData.fixedPosition !== undefined) {
                // Shift all existing positions >= fixedPosition upward by 1 to make room,
                // excluding the note being saved (relevant in edit mode).
                await tx
                    .update(noteOrder)
                    .set({ position: sql`${noteOrder.position} + 1` })
                    .where(
                        and(
                            eq(noteOrder.userId, userId),
                            gte(noteOrder.position, noteData.fixedPosition),
                            ...(existing ? [sql`${noteOrder.noteId} != ${noteData.noteId}`] : []),
                        ),
                    );

                await tx
                    .insert(noteOrder)
                    .values({ userId, noteId: noteData.noteId, position: noteData.fixedPosition })
                    .onConflictDoUpdate({
                        target: [noteOrder.userId, noteOrder.noteId],
                        set: { position: noteData.fixedPosition },
                    });
            } else {
                await tx
                    .delete(noteOrder)
                    .where(and(eq(noteOrder.userId, userId), eq(noteOrder.noteId, noteData.noteId)));
            }

            if (uploadedFiles.length > 0) {
                await tx.insert(noteFiles).values(
                    uploadedFiles.map((f) => ({
                        id: f.id,
                        noteId: noteData.noteId,
                        fileName: f.name,
                        fileType: f.type,
                        fileSize: f.size,
                    })),
                );
            }
        });

        console.log(`Transaction committed successfully`);
    } catch (e) {
        console.error(`Transaction failed:`, e);
        // Transaction failed — remove any files we already wrote to disk.
        if (uploadedFiles.length > 0) {
            await Promise.allSettled(
                uploadedFiles.map((f) => rm(noteFilePath(noteData.noteId, f.id), { force: true })),
            );
        }
        throw e;
    }
}

export async function acquireNoteLock(userId: string, noteId: string) {
    console.log(`START acquireNoteLock - userId: ${userId}, noteId: ${noteId}`);
    const existing = await assertEditAccessIfExists(noteId, userId, {
        editingBy: note.editingBy,
        text: note.text,
        updatedAt: note.updatedAt,
    });

    if (!existing) {
        console.error(`FAILED - Note not found`);
        throw new Error('Note not found');
    }

    return db.transaction(async (tx) => {
        const now = new Date();
        const lockedUntil = new Date(now.getTime() + lockTimeoutMs);

        // Atomically acquire: succeed if unlocked, expired, or already held by this user.
        const updated = await tx
            .update(note)
            .set({ editingBy: userId, lockedUntil })
            .where(
                and(
                    eq(note.id, noteId),
                    or(isNull(note.editingBy), lt(note.lockedUntil, now), eq(note.editingBy, userId)),
                ),
            )
            .returning({ id: note.id });

        if (updated.length === 0) {
            console.error(`FAILED - Lock held by: ${existing.editingBy}`);
            throw new Error(`Locked: ${existing.editingBy}`);
        }

        console.log(`SUCCESS - Lock acquired for ${userId}`);

        return {
            text: existing.text,
            updatedAt: existing.updatedAt,
        };
    });
}

export async function releaseNoteLock(userId: string, noteId: string): Promise<void> {
    console.log(`START releaseNoteLock - userId: ${userId}, noteId: ${noteId}`);

    await db
        .update(note)
        .set({ editingBy: null, lockedUntil: null })
        .where(and(eq(note.id, noteId), eq(note.editingBy, userId)));

    console.log(`Lock released`);
}

export async function refreshNoteLock(userId: string, noteId: string): Promise<void> {
    console.log(`START refreshNoteLock - userId: ${userId}, noteId: ${noteId}`);

    const lockedUntil = new Date(Date.now() + lockTimeoutMs);
    const updated = await db
        .update(note)
        .set({ lockedUntil })
        .where(and(eq(note.id, noteId), eq(note.editingBy, userId)))
        .returning({ id: note.id });

    if (updated.length === 0) {
        console.error(`FAILED - No lock held by user ${userId}`);
        throw new Error('Lock not held');
    }

    console.log(`SUCCESS - Lock refreshed until ${lockedUntil.toISOString()}`);
}

export async function getNoteHistory(userId: string, noteId: string): Promise<Array<{ id: number; text: string; createdAt: Date }>> {
    console.log(`START getNoteHistory - userId: ${userId}, noteId: ${noteId}`);
    await assertEditAccessIfExists(noteId, userId);

    const history = await db
        .select({ id: noteHistory.id, text: noteHistory.text, createdAt: noteHistory.createdAt })
        .from(noteHistory)
        .where(eq(noteHistory.noteId, noteId))
        .orderBy(desc(noteHistory.createdAt));

    console.log(`Retrieved ${history.length} history entries`);
    return history;
}

export async function deleteNote(userId: string, noteId: string): Promise<void> {
    console.log(`START deleteNote - userId: ${userId}, noteId: ${noteId}`);

    const [existing] = await db
        .select({ owner: note.owner })
        .from(note)
        .where(eq(note.id, noteId));

    if (existing && existing.owner !== userId) {
        console.error(`FAILED - Forbidden. Owner: ${existing.owner}, Requester: ${userId}`);
        throw new Error('Forbidden');
    }

    const files = await db
        .select({ id: noteFiles.id })
        .from(noteFiles)
        .where(eq(noteFiles.noteId, noteId));

    console.log(`Deleting note with ${files.length} files`);
    await db.delete(note).where(eq(note.id, noteId));

    if (files.length > 0) {
        await rm(noteDirPath(noteId), { recursive: true, force: true });
    }

    console.log(`SUCCESS - Note and files deleted`);
}

async function uploadFiles(
    noteId: string,
    files?: { id: string; name: string; type: string; size: number; stream: ReadableStream<Uint8Array> }[],
) {
    if (!files || files.length === 0) {
        console.log(`No files to upload`);
        return [];
    }

    console.log(`Starting upload for ${files.length} files to noteId: ${noteId}`);
    const noteDir = noteDirPath(noteId);
    await mkdir(noteDir, { recursive: true });

    const uploadedFiles: UploadedFile[] = [];
    for (const file of files) {
        console.log(`  → Uploading: ${file.name} (${file.size} bytes)`);
        await pipeline(
            Readable.fromWeb(file.stream as Parameters<typeof Readable.fromWeb>[0]),
            createWriteStream(noteFilePath(noteId, file.id)),
        );
        uploadedFiles.push({ id: file.id, name: file.name, type: file.type, size: file.size });
    }

    console.log(`All ${uploadedFiles.length} files uploaded successfully`);
    return uploadedFiles;
}

async function assertEditAccessIfExists<TExtra extends ExtraFieldColumns = {}>(
    noteId: string,
    userId: string,
    extraFields: TExtra = {} as TExtra,
) {
    const [existing] = await db
        .select({ owner: note.owner, ...extraFields })
        .from(note)
        .where(eq(note.id, noteId));

    if (existing && existing.owner !== userId) {
        const [collab] = await db
            .select({ right: collaborator.right })
            .from(collaborator)
            .where(and(eq(collaborator.noteId, noteId), eq(collaborator.userId, userId)));

        if (!collab) {
            console.error(`Access denied - Not a collaborator on note ${noteId}`);
            throw new Error('Forbidden');
        }

        if (collab.right !== 'edit') {
            console.error(`Access denied - No edit permission for user ${userId} on note ${noteId}`);
            throw new Error('Forbidden');
        }

        console.log(`Access allowed - Collaborator with edit right`);
    }

    return existing;
}

async function saveNoteBackup(tx: Tx, noteId: string, text: string): Promise<void> {
    console.log(`Creating backup for noteId: ${noteId}`);
    await tx.insert(noteHistory).values({ noteId, text });

    const toKeep = await tx
        .select({ id: noteHistory.id })
        .from(noteHistory)
        .where(eq(noteHistory.noteId, noteId))
        .orderBy(desc(noteHistory.createdAt))
        .limit(noteHistoryLimit);

    console.log(`  → Keeping ${toKeep.length} of ${noteHistoryLimit} history entries`);

    await tx
        .delete(noteHistory)
        .where(and(
            eq(noteHistory.noteId, noteId),
            notInArray(noteHistory.id, toKeep.map((r) => r.id)),
        ));
}
