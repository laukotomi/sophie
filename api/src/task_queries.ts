import { db } from './db/index.js';
import { task, taskCollaborator, taskAlert } from './db/schema.js';
import { and, eq } from 'drizzle-orm';
import { TaskData } from './models.js';

export async function editOrCreateTask(
    userId: string,
    isEdit: boolean,
    taskData: TaskData,
) {
    console.log(`START editOrCreateTask - userId: ${userId}, operation: ${isEdit ? 'edit' : 'create'}, taskId: ${taskData.taskId}`);
    if (isEdit)
        await assertEditAccess(userId, taskData.taskId);

    const taskDbData = {
        text: taskData.text,
        rrule: taskData.rrule,
        dueAt: taskData.dueAt,
        color: taskData.color,
        recurringGroupId: taskData.recurringGroupId,
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
    console.log(`SUCCESS - Transaction committed`);
}

export async function deleteTask(userId: string, taskId: string): Promise<void> {
    console.log(`START deleteTask - userId: ${userId}, taskId: ${taskId}`);
    await assertEditAccess(userId, taskId);
    await db.delete(task).where(eq(task.id, taskId));
    console.log(`SUCCESS - Task deleted`);
}

export async function deleteTaskGroup(userId: string, taskId: string, groupId: string): Promise<void> {
    console.log(`START deleteTaskGroup - userId: ${userId}, taskId: ${taskId}, groupId: ${groupId}`);
    await assertEditAccess(userId, taskId);
    await db.delete(task).where(eq(task.recurringGroupId, groupId));
    console.log(`SUCCESS - Task group deleted`);
}

export async function setTaskDone(
    userId: string,
    taskId: string,
    doneAt: Date | null,
) {
    console.log(`START setTaskDone - userId: ${userId}, taskId: ${taskId}, doneAt: ${doneAt?.toISOString() ?? 'null'}`);
    await assertViewAccess(userId, taskId);

    await db.update(task)
        .set({ doneAt: doneAt })
        .where(and(eq(task.id, taskId)));
    console.log(`SUCCESS - Task done status updated`);
}

async function assertEditAccess(userId: string, taskId: string) {
    const [existing] = await db
        .select({ id: task.id, owner: task.owner })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) {
        console.error(`Task not found: ${taskId}`);
        throw new Error('Task not found');
    }
    if (existing.owner !== userId) {
        console.error(`Access denied - Owner: ${existing.owner}, Requester: ${userId}`);
        throw new Error('Forbidden');
    }
}

async function assertViewAccess(userId: string, taskId: string) {
    const [existing] = await db
        .select({
            owner: task.owner,
        })
        .from(task)
        .where(eq(task.id, taskId));

    if (!existing) {
        console.error(`Task not found: ${taskId}`);
        throw new Error('Task not found');
    }

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
        if (!collab) {
            console.error(`Access denied - Not a collaborator on task ${taskId}`);
            throw new Error('Forbidden');
        }
    }

    return existing;
}