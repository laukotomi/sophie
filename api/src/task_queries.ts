import { db } from './db/index.js';
import { randomUUID } from "crypto";
import { task, taskCollaborator, taskAlert } from './db/schema.js';
import { and, eq, isNull, isNotNull } from 'drizzle-orm';
import rrulePkg from 'rrule';
import { parseDateISOString } from './utils.js';
import { AlertInput, TaskData } from './models.js';
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

export async function editOrCreateTask(
    userId: string,
    taskId: string | null,
    taskData: TaskData,
): Promise<string> {
    const isEdit = typeof taskId === 'string' && taskId.length > 0;

    if (!isEdit)
        taskId = randomUUID();
    else
        taskId = taskId as string;

    if (isEdit)
        await assertEditAccess(userId, taskId);

    const taskDbData = {
        text: taskData.text,
        rrule: taskData.rrule,
        dueAt: taskData.dueAt,
        color: taskData.color,
    }

    await db.transaction(async (tx) => {
        if (isEdit) {
            await tx.update(task)
                .set(taskData)
                .where(eq(task.id, taskId));
        }
        else {
            await tx.insert(task).values({
                id: taskId,
                owner: userId,
                ...taskDbData
            });
        }

        if (isEdit) {
            await tx.delete(taskCollaborator).where(eq(taskCollaborator.taskId, taskId));
            await tx.delete(taskAlert).where(eq(taskAlert.taskId, taskId));
        }

        if (taskData.collaboratorIds.length > 0) {
            await tx.insert(taskCollaborator).values(
                taskData.collaboratorIds.map((uid) => ({ userId: uid, taskId })),
            );
        }

        if (taskData.alerts.length > 0) {
            await tx.insert(taskAlert).values(
                taskData.alerts.map((a) =>
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

export type NextTaskInfo = { nextTaskId: string; nextDueAt: Date };

export async function setTaskDone(
    userId: string,
    taskId: string,
    done: boolean,
): Promise<NextTaskInfo | null> {
    const existing = await assertViewAccess(userId, taskId);

    const updated = await db.update(task)
        .set({ doneAt: done ? new Date() : null })
        .where(and(eq(task.id, taskId), done ? isNull(task.doneAt) : isNotNull(task.doneAt)))
        .returning({ id: task.id });

    if (!updated.length || !done || !existing.rrule || !existing.dueAt) return null;

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

    const taskData: TaskData = {
        ...existing,
        dueAt: nextDueAt.toISOString(),
        collaboratorIds: collabs.map((c) => c.userId),
        alerts,
    }

    const nextTaskId = await editOrCreateTask(
        existing.owner,
        null,
        taskData
    );

    return { nextTaskId, nextDueAt };
}

async function assertEditAccess(userId: string, taskId: string) {
    const [existing] = await db
        .select({ id: task.id, owner: task.owner })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) throw new Error('Task not found');
    if (existing.owner !== userId) throw new Error('Forbidden');
}

async function assertViewAccess(userId: string, taskId: string) {
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

    return existing;
}