import { db } from './db/index.js';
import { user } from './db/auth.schema.js';
import { note, collaborator, alert as alertTable, noteHistory } from './db/schema.js';
import { eq, inArray, and, desc, notInArray } from 'drizzle-orm';

type Tx = Parameters<Parameters<(typeof db)['transaction']>[0]>[0];

export async function getDashboardData(userId: string) {
    const [users, ownedNotes, collaboratedNotes] = await Promise.all([
        db
            .select({ id: user.id, name: user.name, email: user.email })
            .from(user),

        db
            .select({
                id: note.id,
                text: note.text,
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

    const [alerts, collaborators] = noteIds.length > 0
        ? await Promise.all([
            db
                .select({ id: alertTable.id, noteId: alertTable.noteId, time: alertTable.time })
                .from(alertTable)
                .where(inArray(alertTable.noteId, noteIds)),

            db
                .select({
                    noteId: collaborator.noteId,
                    right: collaborator.right,
                    userId: user.id,
                    userName: user.name,
                    userEmail: user.email,
                })
                .from(collaborator)
                .innerJoin(user, eq(user.id, collaborator.userId))
                .where(inArray(collaborator.noteId, noteIds)),
        ])
        : [[], []];

    const alertsByNoteId = Map.groupBy(alerts, (a) => a.noteId);
    const collaboratorsByNoteId = Map.groupBy(collaborators, (c) => c.noteId);

    const notes = [
        ...ownedNotes.map((n) => ({ ...n, right: 'edit' as const, isOwner: true })),
        ...collaboratedNotes.map((n) => ({ ...n, isOwner: false })),
    ]
        .sort((a, b) => b.updatedAt.getTime() - a.updatedAt.getTime())
        .map((n) => ({
            ...n,
            alerts: alertsByNoteId.get(n.id) ?? [],
            collaborators: (collaboratorsByNoteId.get(n.id) ?? []).map((c) => ({
                id: c.userId,
                name: c.userName,
                email: c.userEmail,
                right: c.right,
            })),
        }));

    return { users, notes };
}

export async function editOrCreateNote(
    userId: string,
    noteId: string | null,
    text: string,
    collaboratorsJson?: string,
    alertsJson?: string,
) {
    const isEdit = typeof noteId === 'string' && noteId.length > 0;

    // Pre-parse JSON before the transaction to fail fast on bad input
    const collabs = collaboratorsJson
        ? (JSON.parse(collaboratorsJson) as { userId: string; right: 'view' | 'edit' }[])
        : [];
    const alertItems = alertsJson
        ? (JSON.parse(alertsJson) as { date: string; hours: number; minutes: number }[])
        : [];

    await db.transaction(async (tx) => {
        let targetNoteId: string;

        if (isEdit) {
            const existing = await assertEditAccess(tx, noteId as string, userId);
            await saveNoteBackup(tx, noteId as string, existing.text);

            await tx
                .update(note)
                .set({ text: text.trim() })
                .where(eq(note.id, noteId as string));

            targetNoteId = noteId as string;

            await tx.delete(alertTable).where(eq(alertTable.noteId, targetNoteId));
            await tx.delete(collaborator).where(eq(collaborator.noteId, targetNoteId));
        } else {
            const [newNote] = await tx
                .insert(note)
                .values({ text: text.trim(), owner: userId })
                .returning({ id: note.id });
            targetNoteId = newNote.id;
        }

        if (collabs.length > 0) {
            await tx.insert(collaborator).values(
                collabs.map((c) => ({ noteId: targetNoteId, userId: c.userId, right: c.right })),
            );
        }

        if (alertItems.length > 0) {
            await tx.insert(alertTable).values(
                alertItems.map((a) => ({
                    noteId: targetNoteId,
                    time: `${a.date}T${String(a.hours).padStart(2, '0')}:${String(a.minutes).padStart(2, '0')}:00`,
                })),
            );
        }
    });
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
