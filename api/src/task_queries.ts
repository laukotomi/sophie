import { db } from './db/index.js';
import { randomUUID } from "crypto";
import { task, taskCollaborator, taskAlert } from './db/schema.js';
import { and, eq } from 'drizzle-orm';
import rrulePkg from 'rrule';
import { parseDateISOString } from './utils.js';
const { RRule } = rrulePkg;

function getNextOccurrence(rruleStr: string, currentDueAt: Date): Date | null {
    try {
        const normalized = rruleStr.startsWith('RRULE:') ? rruleStr : `RRULE:${rruleStr}`;
        const rule = RRule.fromString(normalized);
        const r = new RRule({ ...rule.origOptions, dtstart: currentDueAt });
        return r.after(currentDueAt, false);
    } catch {
        return null;
    }
}

type AlertInput =
    | { type: 'absolute'; alertAt: Date }
    | { type: 'relative'; timeBefore: string }; // 'HH:MM:SS'

export async function createTask(
    userId: string,
    text: string,
    rrule: string | null,
    dueAt: string,
    color: string | null,
    collaboratorIds: string[],
    alerts: AlertInput[],
): Promise<string> {
    const taskId = randomUUID();
    await db.transaction(async (tx) => {
        await tx.insert(task).values({
            id: taskId,
            owner: userId,
            text,
            rrule,
            dueAt,
            color,
        });

        if (collaboratorIds.length > 0) {
            await tx.insert(taskCollaborator).values(
                collaboratorIds.map((uid) => ({ userId: uid, taskId })),
            );
        }

        if (alerts.length > 0) {
            await tx.insert(taskAlert).values(
                alerts.map((a) =>
                    a.type === 'absolute'
                        ? { taskId, alertAt: a.alertAt, timeBefore: null }
                        : { taskId, alertAt: null, timeBefore: a.timeBefore },
                ),
            );
        }
    });

    return taskId;
}
export async function deleteTask(userId: string, taskId: string): Promise<void> {
    const [existing] = await db
        .select({ id: task.id, owner: task.owner })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) throw new Error('Task not found');
    if (existing.owner !== userId) throw new Error('Forbidden');

    await db.delete(task).where(eq(task.id, taskId));
}

export async function updateTask(
    userId: string,
    taskId: string,
    text: string,
    rrule: string | null,
    dueAt: string,
    color: string | null,
    collaboratorIds: string[],
    alerts: AlertInput[],
): Promise<void> {
    const [existing] = await db
        .select({ id: task.id, owner: task.owner })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) throw new Error('Task not found');
    if (existing.owner !== userId) throw new Error('Forbidden');

    await db.transaction(async (tx) => {
        await tx.update(task)
            .set({ text, rrule, dueAt, color })
            .where(eq(task.id, taskId));

        await tx.delete(taskCollaborator).where(eq(taskCollaborator.taskId, taskId));
        if (collaboratorIds.length > 0) {
            await tx.insert(taskCollaborator).values(
                collaboratorIds.map((uid) => ({ userId: uid, taskId })),
            );
        }

        await tx.delete(taskAlert).where(eq(taskAlert.taskId, taskId));
        if (alerts.length > 0) {
            await tx.insert(taskAlert).values(
                alerts.map((a) =>
                    a.type === 'absolute'
                        ? { taskId, alertAt: a.alertAt, timeBefore: null }
                        : { taskId, alertAt: null, timeBefore: a.timeBefore },
                ),
            );
        }
    });
}

export type NextTaskInfo = { nextTaskId: string; nextDueAt: Date };

export async function setTaskDone(
    userId: string,
    taskId: string,
    done: boolean,
): Promise<NextTaskInfo | null> {
    const [existing] = await db
        .select({
            id: task.id,
            owner: task.owner,
            text: task.text,
            rrule: task.rrule,
            dueAt: task.dueAt,
            color: task.color,
        })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) throw new Error('Task not found');

    if (existing.owner !== userId) {
        const [collab] = await db
            .select({ id: taskCollaborator.id })
            .from(taskCollaborator)
            .where(
                and(
                    eq(taskCollaborator.taskId, taskId),
                    eq(taskCollaborator.userId, userId),
                ),
            );
        if (!collab) throw new Error('Forbidden');
    }

    await db.update(task)
        .set({ doneAt: done ? new Date() : null })
        .where(eq(task.id, taskId));

    if (!done || !existing.rrule || !existing.dueAt) return null;

    const nextDueAt = getNextOccurrence(existing.rrule, parseDateISOString(existing.dueAt));
    if (!nextDueAt) return null;

    const [collabs, alertRows] = await Promise.all([
        db.select({ userId: taskCollaborator.userId })
            .from(taskCollaborator)
            .where(eq(taskCollaborator.taskId, taskId)),
        db.select({ timeBefore: taskAlert.timeBefore })
            .from(taskAlert)
            .where(eq(taskAlert.taskId, taskId)),
    ]);

    const alerts: AlertInput[] = alertRows
        .filter((a) => a.timeBefore !== null)
        .map((a) => ({ type: 'relative' as const, timeBefore: a.timeBefore! }));

    const nextTaskId = await createTask(
        existing.owner,
        existing.text,
        existing.rrule,
        nextDueAt.toISOString(),
        existing.color,
        collabs.map((c) => c.userId),
        alerts,
    );

    return { nextTaskId, nextDueAt };
}