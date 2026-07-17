import { db } from './db/index.js';
import { task, taskCollaborator, taskAlert } from './db/schema.js';
import { and, eq } from 'drizzle-orm';
import { TaskData } from './models.js';

export async function editOrCreateTask(
    userId: string,
    isEdit: boolean,
    taskData: TaskData,
) {
    if (isEdit)
        await assertEditAccess(userId, taskData.taskId);

    const taskDbData = {
        text: taskData.text,
        rrule: taskData.rrule,
        dueAt: taskData.dueAt,
        color: taskData.color,
    }

    await db.transaction(async (tx) => {
        if (isEdit) {
            await tx.update(task)
                .set({
                    updatedAt: taskData.timestamp,
                    ...taskDbData
                })
                .where(eq(task.id, taskData.taskId));
        }
        else {
            await tx.insert(task).values({
                id: taskData.taskId,
                owner: userId,
                recurringGroupId: taskData.rrule ? (taskData.recurringGroupId ?? taskData.taskId) : null,
                createdAt: taskData.timestamp,
                updatedAt: taskData.timestamp,
                ...taskDbData
            });
        }

        if (isEdit) {
            await tx.delete(taskCollaborator).where(eq(taskCollaborator.taskId, taskData.taskId));
            await tx.delete(taskAlert).where(eq(taskAlert.taskId, taskData.taskId));
        }

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
}

export async function deleteTask(userId: string, taskId: string): Promise<void> {
    await assertEditAccess(userId, taskId);
    await db.delete(task).where(eq(task.id, taskId));
}

export async function deleteTaskGroup(userId: string, taskId: string, groupId: string): Promise<void> {
    await assertEditAccess(userId, taskId);
    await db.delete(task).where(eq(task.recurringGroupId, groupId));
}

export async function setTaskDone(
    userId: string,
    taskId: string,
    doneAt: Date | null,
) {
    await assertViewAccess(userId, taskId);

    await db.update(task)
        .set({ doneAt: doneAt })
        .where(and(eq(task.id, taskId)));
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
            owner: task.owner,
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