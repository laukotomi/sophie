import { db } from "$lib/server/db";
import { user } from "$lib/server/db/auth.schema";
import { note, collaborator, alert as alertTable } from "$lib/server/db/schema";
import { eq, ne, inArray, and } from "drizzle-orm";

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

export async function editOrCreateNote(userId: string, noteId: string | null, text: string, collaboratorsJson?: string, alertsJson?: string) {
    const isEdit = typeof noteId === 'string' && noteId.length > 0;

    let targetNoteId: string;

    if (isEdit) {
        // Verify the user has edit rights
        const [existing] = await db
            .select({ id: note.id, owner: note.owner })
            .from(note)
            .where(eq(note.id, noteId as string));

        if (!existing) throw new Error('Note not found');

        const isOwner = existing.owner === userId;
        if (!isOwner) {
            const [collab] = await db
                .select({ right: collaborator.right })
                .from(collaborator)
                .where(and(
                    eq(collaborator.noteId, noteId as string),
                    eq(collaborator.userId, userId),
                ));
            if (!collab || collab.right !== 'edit') {
                throw new Error('Forbidden');
            }
        }

        await db
            .update(note)
            .set({ text: text.trim() })
            .where(eq(note.id, noteId as string));

        targetNoteId = noteId as string;

        // Replace alerts and collaborators
        await db.delete(alertTable).where(eq(alertTable.noteId, targetNoteId));
        await db.delete(collaborator).where(eq(collaborator.noteId, targetNoteId));
    } else {
        const [newNote] = await db
            .insert(note)
            .values({ text: text.trim(), owner: userId })
            .returning({ id: note.id });
        targetNoteId = newNote.id;
    }

    if (collaboratorsJson && typeof collaboratorsJson === 'string') {
        const collaborators = JSON.parse(collaboratorsJson) as { userId: string; right: 'view' | 'edit' }[];
        if (collaborators.length > 0) {
            await db.insert(collaborator).values(
                collaborators.map((c) => ({ noteId: targetNoteId, userId: c.userId, right: c.right }))
            );
        }
    }

    if (alertsJson && typeof alertsJson === 'string') {
        const alerts = JSON.parse(alertsJson) as { date: string; hours: number; minutes: number }[];
        if (alerts.length > 0) {
            await db.insert(alertTable).values(
                alerts.map((a) => ({
                    noteId: targetNoteId,
                    time: `${a.date}T${String(a.hours).padStart(2, '0')}:${String(a.minutes).padStart(2, '0')}:00`,
                }))
            );
        }
    }

}