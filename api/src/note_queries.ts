import { db } from './db/index.js';
import { user } from './db/auth.schema.js';
import { note, collaborator, noteHistory, noteOrder, noteFiles } from './db/schema.js';
import { eq, inArray, and, desc, notInArray, gte, sql, asc } from 'drizzle-orm';
import { randomUUID } from 'node:crypto';
import { mkdir, rm } from 'node:fs/promises';
import { createWriteStream } from 'node:fs';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { noteDirPath, noteFilePath } from './utils.js';

type Tx = Parameters<Parameters<(typeof db)['transaction']>[0]>[0];
type UploadedFile = { id: string; name: string; type: string; size: number };

export async function getDashboardData(userId: string) {
    const [users, ownedNotes, collaboratedNotes] = await Promise.all([
        db
            .select({ id: user.id, name: user.name, email: user.email })
            .from(user)
            .orderBy(asc(user.name)),

        db
            .select({
                id: note.id,
                text: note.text,
                color: note.color,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                ownerId: note.owner,
            })
            .from(note)
            .where(eq(note.owner, userId)),

        db
            .select({
                id: note.id,
                text: note.text,
                color: note.color,
                createdAt: note.createdAt,
                updatedAt: note.updatedAt,
                ownerId: note.owner,
                right: collaborator.right,
            })
            .from(note)
            .innerJoin(collaborator, eq(collaborator.noteId, note.id))
            .where(eq(collaborator.userId, userId)),
    ]);

    const noteIds = [
        ...ownedNotes.map((n) => n.id),
        ...collaboratedNotes.map((n) => n.id),
    ];

    const [collaborators, positions, files] = noteIds.length > 0
        ? await Promise.all([
            db
                .select({
                    noteId: collaborator.noteId,
                    right: collaborator.right,
                    userId: collaborator.userId,
                })
                .from(collaborator)
                .where(inArray(collaborator.noteId, noteIds)),

            db
                .select({ noteId: noteOrder.noteId, position: noteOrder.position })
                .from(noteOrder)
                .where(and(eq(noteOrder.userId, userId), inArray(noteOrder.noteId, noteIds))),

            db
                .select({
                    noteId: noteFiles.noteId,
                    id: noteFiles.id,
                    fileName: noteFiles.fileName,
                    fileSize: noteFiles.fileSize,
                    createdAt: noteFiles.createdAt,
                })
                .from(noteFiles)
                .where(inArray(noteFiles.noteId, noteIds)),
        ])
        : [[], [], []];

    const positionByNoteId = new Map(positions.map((p) => [p.noteId, p.position]));
    const userById = new Map(users.map((u) => [u.id, u]));
    const collaboratorsByNoteId = Map.groupBy(collaborators, (c) => c.noteId);
    const filesByNoteId = Map.groupBy(files, (f) => f.noteId);

    const notes = [
        ...ownedNotes.map((n) => ({ ...n, right: 'edit' as const, isOwner: true })),
        ...collaboratedNotes.map((n) => ({ ...n, isOwner: false })),
    ]
        .sort((a, b) => {
            const posA = positionByNoteId.get(a.id);
            const posB = positionByNoteId.get(b.id);
            if (posA !== undefined && posB !== undefined) return posA - posB;
            if (posA !== undefined) return -1;
            if (posB !== undefined) return 1;
            return b.updatedAt.getTime() - a.updatedAt.getTime();
        })
        .map((n) => ({
            ...n,
            position: positionByNoteId.get(n.id) ?? null,
            color: n.color ?? null,
            collaborators: (collaboratorsByNoteId.get(n.id) ?? []).flatMap((c) => {
                const u = userById.get(c.userId);
                if (!u) return [];
                return [{ id: c.userId, name: u.name, email: u.email, right: c.right }];
            }),
            files: (filesByNoteId.get(n.id) ?? []).map((f) => ({
                id: f.id,
                fileName: f.fileName,
                fileSize: f.fileSize,
                createdAt: f.createdAt,
            })),
        }));

    return { users, notes };
}

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
