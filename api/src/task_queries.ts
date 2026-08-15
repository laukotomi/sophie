import { db } from './db/index.js';
import { task, taskCollaborator, taskAlert } from './db/schema.js';
import { and, eq } from 'drizzle-orm';
import type { AnyPgColumn } from 'drizzle-orm/pg-core';
import { TaskData } from './models.js';

type Task = typeof task.$inferSelect;

type ExtraFieldColumns = {
    [K in keyof Task]?: AnyPgColumn<{ data: Task[K] }>;
};

export async function upsertTask(
    userId: string,
    taskData: TaskData,
) {
    console.log(`START upsertTask - userId: ${userId}, taskId: ${taskData.taskId}`);

    await assertEditAccessIfExists(userId, taskData.taskId);

    const taskDbData = {
        text: taskData.text,
        rrule: taskData.rrule,
        dueAt: taskData.dueAt,
        color: taskData.color,
        recurringGroupId: taskData.recurringGroupId,
    }

    await db.transaction(async (tx) => {
        await tx.insert(task).values({
            id: taskData.taskId,
            owner: userId,
            createdAt: taskData.timestamp,
            updatedAt: taskData.timestamp,
            ...taskDbData
        })
            .onConflictDoUpdate({
                target: [task.id],
                set: {
                    updatedAt: taskData.timestamp,
                    ...taskDbData,
                },
            });

        await tx.delete(taskCollaborator).where(eq(taskCollaborator.taskId, taskData.taskId));
        await tx.delete(taskAlert).where(eq(taskAlert.taskId, taskData.taskId));

        if (taskData.collaboratorIds.length > 0) {
            await tx.insert(taskCollaborator).values(
                taskData.collaboratorIds.map((uid) => ({ userId: uid, taskId: taskData.taskId })),
            );
        }

        if (taskData.alerts.length > 0) {
            await tx.insert(taskAlert).values(
                taskData.alerts.map((a) =>
                    a.type === 'absolute'
                        ? { taskId: taskData.taskId, alertAt: a.alertAt, timeBefore: null }
                        : { taskId: taskData.taskId, alertAt: null, timeBefore: a.timeBefore },
                ),
            );
        }
    });
    console.log(`SUCCESS - Transaction committed`);
}

export async function deleteTask(userId: string, taskId: string): Promise<void> {
    console.log(`START deleteTask - userId: ${userId}, taskId: ${taskId}`);

    await assertEditAccessIfExists(userId, taskId);
    await db.delete(task).where(eq(task.id, taskId));

    console.log(`SUCCESS - Task deleted`);
}

export async function deleteTaskGroup(userId: string, taskId: string) {
    console.log(`START deleteTaskGroup - userId: ${userId}, taskId: ${taskId}`);

    const existing = await assertEditAccessIfExists(userId, taskId, { recurringGroupId: task.recurringGroupId });

    if (existing?.recurringGroupId) {
        await db.delete(task).where(
            and(
                eq(task.recurringGroupId, existing.recurringGroupId),
                eq(task.owner, userId),
            ),
        );
    }
    console.log(`SUCCESS - Task group deleted`);
}

export async function setTaskDone(
    userId: string,
    taskId: string,
    doneAt: Date | null,
) {
    console.log(`START setTaskDone - userId: ${userId}, taskId: ${taskId}, doneAt: ${doneAt?.toISOString() ?? 'null'}`);
    const existing = await assertViewAccessIfExists(userId, taskId);

    if (existing) {
        await db.update(task)
            .set({ doneAt: doneAt })
            .where(and(eq(task.id, taskId)));
    }

    console.log(`SUCCESS - Task done status updated`);
}

async function assertEditAccessIfExists<TExtra extends ExtraFieldColumns = {}>(
    userId: string,
    taskId: string,
    extraFields: TExtra = {} as TExtra,
) {
    const [existing] = await db
        .select({ owner: task.owner, ...extraFields })
        .from(task)
        .where(eq(task.id, taskId));

    if (existing && existing.owner !== userId) {
        console.error(`Access denied - Owner: ${existing.owner}, Requester: ${userId}`);
        throw new Error('Forbidden');
    }

    return existing;
}

async function assertViewAccessIfExists(userId: string, taskId: string) {
    const [existing] = await db
        .select({
            owner: task.owner,
        })
        .from(task)
        .where(eq(task.id, taskId));

    if (existing && existing.owner !== userId) {
        const [collab] = await db
            .select({ id: taskCollaborator.id })
            .from(taskCollaborator)
            .where(
                and(
                    eq(taskCollaborator.taskId, taskId),
                    eq(taskCollaborator.userId, userId),
                ),
            );

        if (!collab) {
            console.error(`Access denied - Not a collaborator on task ${taskId}`);
            throw new Error('Forbidden');
        }
    }

    return existing;
}