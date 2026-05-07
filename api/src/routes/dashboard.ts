import { Hono } from 'hono';
import { requireAuth, type AuthVariables } from '../middleware.js';
import { db } from '../db/index.js';
import { collaborator, note, noteFiles, noteOrder, task, taskAlert, taskCollaborator, user } from '../db/schema.js';
import { asc, eq, and, inArray, or, isNull, gt } from 'drizzle-orm';

const dashboard = new Hono<{ Variables: AuthVariables }>();

dashboard.use(requireAuth);

dashboard.get('/', async (c) => {
    const currentUser = c.get('user');

    try {
        const threeMonthsAgo = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);
        const [users, ownedNotes, collaboratedNotes, ownedTasks, collaboratedTasks] = await Promise.all([
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
                .where(eq(note.owner, currentUser.id)),

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
                .where(eq(collaborator.userId, currentUser.id)),

            db
                .select({
                    id: task.id,
                    text: task.text,
                    rrule: task.rrule,
                    color: task.color,
                    dueAt: task.dueAt,
                    doneAt: task.doneAt,
                    createdAt: task.createdAt,
                    ownerId: task.owner,
                })
                .from(task)
                .where(and(
                    eq(task.owner, currentUser.id),
                    or(isNull(task.doneAt), gt(task.doneAt, threeMonthsAgo)),
                )),

            db
                .select({
                    id: task.id,
                    text: task.text,
                    rrule: task.rrule,
                    color: task.color,
                    dueAt: task.dueAt,
                    doneAt: task.doneAt,
                    createdAt: task.createdAt,
                    ownerId: task.owner,
                })
                .from(task)
                .innerJoin(taskCollaborator, eq(taskCollaborator.taskId, task.id))
                .where(and(
                    eq(taskCollaborator.userId, currentUser.id),
                    or(isNull(task.doneAt), gt(task.doneAt, threeMonthsAgo)),
                )),
        ]);

        const noteIds = [
            ...ownedNotes.map((n) => n.id),
            ...collaboratedNotes.map((n) => n.id),
        ];

        const taskIds = [
            ...ownedTasks.map((t) => t.id),
            ...collaboratedTasks.map((t) => t.id),
        ];

        const [collaborators, positions, files, taskCollaborators, alerts] = await Promise.all([
            noteIds.length > 0
                ? db
                    .select({
                        noteId: collaborator.noteId,
                        right: collaborator.right,
                        userId: collaborator.userId,
                    })
                    .from(collaborator)
                    .where(inArray(collaborator.noteId, noteIds))
                : Promise.resolve([]),

            noteIds.length > 0
                ? db
                    .select({ noteId: noteOrder.noteId, position: noteOrder.position })
                    .from(noteOrder)
                    .where(and(eq(noteOrder.userId, currentUser.id), inArray(noteOrder.noteId, noteIds)))
                : Promise.resolve([]),

            noteIds.length > 0
                ? db
                    .select({
                        noteId: noteFiles.noteId,
                        id: noteFiles.id,
                        fileName: noteFiles.fileName,
                        fileSize: noteFiles.fileSize,
                        createdAt: noteFiles.createdAt,
                    })
                    .from(noteFiles)
                    .where(inArray(noteFiles.noteId, noteIds))
                : Promise.resolve([]),

            taskIds.length > 0
                ? db
                    .select({
                        taskId: taskCollaborator.taskId,
                        userId: taskCollaborator.userId,
                    })
                    .from(taskCollaborator)
                    .where(inArray(taskCollaborator.taskId, taskIds))
                : Promise.resolve([]),

            taskIds.length > 0
                ? db
                    .select({
                        id: taskAlert.id,
                        taskId: taskAlert.taskId,
                        alertAt: taskAlert.alertAt,
                        timeBefore: taskAlert.timeBefore,
                    })
                    .from(taskAlert)
                    .where(inArray(taskAlert.taskId, taskIds))
                : Promise.resolve([])
        ]);

        const positionByNoteId = new Map(positions.map((p) => [p.noteId, p.position]));
        const userById = new Map(users.map((u) => [u.id, u]));
        const collaboratorsByNoteId = Map.groupBy(collaborators, (c) => c.noteId);
        const filesByNoteId = Map.groupBy(files, (f) => f.noteId);
        const taskCollaboratorsByTaskId = Map.groupBy(taskCollaborators, (c) => c.taskId);
        const alertsByTaskId = Map.groupBy(alerts, (a) => a.taskId);

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

        const tasks = [
            ...ownedTasks.map((t) => ({ ...t, isOwner: true })),
            ...collaboratedTasks.map((t) => ({ ...t, isOwner: false })),
        ]
            .sort((a, b) => {
                if (a.doneAt && !b.doneAt) return 1;
                if (!a.doneAt && b.doneAt) return -1;
                if (!a.dueAt && b.dueAt) return -1;
                if (a.dueAt && !b.dueAt) return 1;
                if (a.dueAt && b.dueAt) {
                    const dueDiff = a.dueAt!.getTime() - b.dueAt!.getTime();
                    if (dueDiff !== 0) return dueDiff;
                }
                return b.createdAt.getTime() - a.createdAt.getTime();
            })
            .map((t) => ({
                ...t,
                collaborators: (taskCollaboratorsByTaskId.get(t.id) ?? []).flatMap((c) => {
                    const u = userById.get(c.userId);
                    if (!u) return [];
                    return [{ id: c.userId, name: u.name, email: u.email }];
                }),
                alerts: (alertsByTaskId.get(t.id) ?? []).map((a) => ({
                    id: a.id,
                    alertAt: a.alertAt,
                    timeBefore: a.timeBefore,
                })),
            }));

        return c.json({ user: currentUser, users, notes, tasks });
    } catch (e) {
        console.error('[GET /api/dashboard] failed:', e);
        return c.json({ error: 'Failed to load dashboard' }, 500);
    }
});

export default dashboard;
