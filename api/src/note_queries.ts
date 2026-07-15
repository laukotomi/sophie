import { db } from './db/index.js';
import { note, collaborator, noteHistory, noteOrder, noteFiles } from './db/schema.js';
import { eq, and, or, isNull, lt, desc, notInArray, gte, sql } from 'drizzle-orm';
import { mkdir, rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { noteDirPath, noteFilePath } from './utils.js';
import { NoteFormData } from './models.js';

type Tx = Parameters<Parameters<(typeof db)['transaction']>[0]>[0];
type Db = typeof db;
type UploadedFile = { id: string; name: string; type: string; size: number };

export async function editOrCreateNote(
    userId: string,
    isEdit: boolean,
    noteData: NoteFormData
) {
    // Upload files to disk before the transaction so we don't hold the DB
    // connection open during slow I/O. If the transaction later fails we clean up.
    const { uploadedFiles } = await uploadFiles(noteData.noteId, noteData.files);

    const noteDbData = {
        text: noteData.text,
        color: noteData.color,
        dontFold: noteData.dontFold,
        todoList: noteData.todoList,
    }

    try {
        await db.transaction(async (tx) => {

            if (isEdit) {
                const existing = await assertEditAccess(tx, noteData.noteId, userId);

                const holdsLock = existing.editingBy === userId;
                if (!holdsLock) throw new Error('Lock required');

                await saveNoteBackup(tx, noteData.noteId, existing.text);

                await tx
                    .update(note)
                    .set({ ...noteDbData, editingBy: null, lockedUntil: null })
                    .where(eq(note.id, noteData.noteId));

                await tx.delete(collaborator).where(eq(collaborator.noteId, noteData.noteId));
            } else {
                await tx
                    .insert(note)
                    .values({ id: noteData.noteId, ...noteDbData, owner: userId });
            }

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
                            ...(isEdit ? [sql`${noteOrder.noteId} != ${noteData.noteId}`] : []),
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
    } catch (e) {
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
    return db.transaction(async (tx) => {
        const existing = await assertEditAccess(tx, noteId, userId);

        const now = new Date();
        const lockedUntil = new Date(now.getTime() + 60_000);

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
            const [locked] = await tx
                .select({ editingBy: note.editingBy })
                .from(note)
                .where(eq(note.id, noteId));
            throw new Error(`Locked:${locked?.editingBy ?? 'unknown'}`);
        }

        return {
            text: existing.text,
            updatedAt: existing.updatedAt,
        };
    });
}

export async function releaseNoteLock(userId: string, noteId: string): Promise<void> {
    await db
        .update(note)
        .set({ editingBy: null, lockedUntil: null })
        .where(and(eq(note.id, noteId), eq(note.editingBy, userId)));
}

export async function refreshNoteLock(userId: string, noteId: string): Promise<void> {
    const lockedUntil = new Date(Date.now() + 60_000);
    const updated = await db
        .update(note)
        .set({ lockedUntil })
        .where(and(eq(note.id, noteId), eq(note.editingBy, userId)))
        .returning({ id: note.id });

    if (updated.length === 0) throw new Error('Lock not held');
}

export async function getNoteHistory(userId: string, noteId: string): Promise<Array<{ id: number; text: string; createdAt: Date }>> {
    await assertEditAccess(db, noteId, userId);
    return db
        .select({ id: noteHistory.id, text: noteHistory.text, createdAt: noteHistory.createdAt })
        .from(noteHistory)
        .where(eq(noteHistory.noteId, noteId))
        .orderBy(desc(noteHistory.createdAt));
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
    files?: { id: string; name: string; type: string; size: number; stream: ReadableStream<Uint8Array> }[],
): Promise<{ uploadedFiles: UploadedFile[] }> {
    if (!files || files.length === 0) return { uploadedFiles: [] };

    const noteDir = noteDirPath(noteId);
    await mkdir(noteDir, { recursive: true });

    const uploadedFiles: UploadedFile[] = [];
    for (const file of files) {
        await pipeline(
            Readable.fromWeb(file.stream as Parameters<typeof Readable.fromWeb>[0]),
            createWriteStream(noteFilePath(noteId, file.id)),
        );
        uploadedFiles.push({ id: file.id, name: file.name, type: file.type, size: file.size });
    }

    return { uploadedFiles };
}

async function assertEditAccess(
    tx: Tx | Db,
    noteId: string,
    userId: string,
): Promise<{ id: string; owner: string; text: string; editingBy: string | null; lockedUntil: Date | null; updatedAt: Date }> {
    const [existing] = await tx
        .select({ id: note.id, owner: note.owner, text: note.text, editingBy: note.editingBy, lockedUntil: note.lockedUntil, updatedAt: note.updatedAt })
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
