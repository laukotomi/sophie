import { describe, expect, it } from 'vitest';
import { randomUUID } from 'crypto';
import { loginTestUser, requestJson, TEST_USER1, TEST_USER2 } from './harness';
import { count, eq } from 'drizzle-orm';
import { task as taskTable } from '../src/db/schema';
import { TaskData } from '../src/models';
import { db } from '../src/db';

describe('Task API integration', () => {
    it('rejects unauthenticated task writes', async () => {
        const res = await requestJson('/api/tasks', {
            method: 'POST',
        });

        const body = await res.json();

        expect(res.status).toBe(401);
        expect(body).toEqual({ error: 'Unauthorized' });
    });

    it('can delete a non-existent task without error', async () => {
        const token = await loginTestUser(TEST_USER1);
        await deleteTask(false, token, 'non-existent-task-id');
    });

    it('can delete a non-existent task group without error', async () => {
        const token = await loginTestUser(TEST_USER1);
        await deleteTask(true, token, 'non-existent-task-id');
    });

    it('can create a task', async () => {
        const token = await loginTestUser(TEST_USER1);
        await createTaskForUser(token);
    });

    it('cannot delete a task that belongs to another user', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const task = await createTaskForUser(token1);

        const res = await requestJson('/api/tasks', {
            token: token2,
            method: 'DELETE',
            body: { taskId: task.taskId },
        });

        expect(res.status).toBe(403);
    });

    it('cannot delete a task group that belongs to another user', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const task = await createTaskForUser(token1);

        const res = await requestJson('/api/tasks/group', {
            token: token2,
            method: 'DELETE',
            body: { taskId: task.taskId },
        });

        expect(res.status).toBe(403);
    });

    it('can delete its own task', async () => {
        const token = await loginTestUser(TEST_USER1);
        const task = await createTaskForUser(token);

        await deleteTask(false, token, task.taskId);
    });

    it('can delete its own task group', async () => {
        const groupName = 'group';
        const token = await loginTestUser(TEST_USER1);
        const task = await createTaskForUser(token, {
            recurringGroupId: groupName,
        });
        await createTaskForUser(token, {
            recurringGroupId: groupName,
        });

        await deleteTask(true, token, task.taskId);
    });

    it('can set task done and undone', async () => {
        const token = await loginTestUser(TEST_USER1);
        const task = await createTaskForUser(token);

        await setTaskDone(token, task.taskId, new Date());
        await setTaskDone(token, task.taskId, null);
    });

    it('can set task done and undone when collaborator', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const task = await createTaskForUser(token1, {
            collaboratorIds: [TEST_USER2.id],
        });

        await setTaskDone(token2, task.taskId, new Date());
        await setTaskDone(token2, task.taskId, null);
    });

    it('can create a task multiple times with the same taskId', async () => {
        const token = await loginTestUser(TEST_USER1);
        const taskId = randomUUID();

        const timestamp = new Date();
        await createTaskForUser(token, { taskId, timestamp });
        await createTaskForUser(token, { taskId, text: 'updated text', timestamp });
    });
});

async function createTaskForUser(token: string, taskData?: Partial<TaskData>) {
    const task: TaskData = {
        taskId: randomUUID(),
        text: 'hello',
        rrule: null,
        dueAt: null,
        color: null,
        collaboratorIds: [],
        alerts: [],
        recurringGroupId: null,
        timestamp: new Date(),
        ...taskData,
    };

    const res = await requestJson('/api/tasks', {
        method: 'POST',
        token: token,
        body: task,
    });

    expect(res.status).toBe(201);

    const [insertedTask] = await db
        .select()
        .from(taskTable)
        .where(eq(taskTable.id, task.taskId))
        .limit(1);

    expect(insertedTask).toBeDefined();

    expect(insertedTask!.id).toBe(task.taskId);
    expect(insertedTask!.text).toBe(task.text);
    expect(insertedTask!.rrule).toBe(task.rrule);
    expect(insertedTask!.color).toBe(task.color);
    expect(insertedTask!.dueAt).toBe(task.dueAt);
    expect(insertedTask!.recurringGroupId).toBe(task.recurringGroupId);
    expect(new Date(insertedTask!.createdAt).toISOString()).toBe(task.timestamp.toISOString());

    return task;
}

async function setTaskDone(token: string, taskId: string, doneAt: Date | null) {
    const res = await requestJson('/api/tasks', {
        method: 'PATCH',
        token: token,
        body: {
            taskId: taskId,
            doneAt: doneAt ? doneAt.toISOString() : null,
        },
    });

    expect(res.status).toBe(204);

    const [updatedTask] = await db
        .select()
        .from(taskTable)
        .where(eq(taskTable.id, taskId))
        .limit(1);

    expect(updatedTask).toBeDefined();

    if (doneAt === null) {
        expect(updatedTask!.doneAt).toBeNull();
    } else {
        expect(updatedTask!.doneAt?.toISOString()).toBe(doneAt.toISOString());
    }
}

async function deleteTask(group: boolean, token: string, taskId: string) {
    const uri = group ? '/api/tasks/group' : '/api/tasks';
    const res = await requestJson(uri, {
        method: 'DELETE',
        token: token,
        body: { taskId: taskId },
    });

    expect(res.status).toBe(204);

    const [{ count: taskCount }] = await db
        .select({ count: count() })
        .from(taskTable)
        .where(eq(taskTable.id, taskId));

    expect(taskCount).toBe(0);
}