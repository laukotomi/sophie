import { Hono } from 'hono';
import { requireAuth, type AuthVariables } from '../middleware.js';
import { deleteTask, editOrCreateTask, setTaskDone } from '../task_queries.js';
import type { NextTaskInfo } from '../task_queries.js';
import { parseDateISOString } from '../utils.js';
import { TaskData, AlertInput } from '../models.js';

async function parseAlertsForm(body: any): Promise<TaskData | null> {
    if (!body) return null;

    const text = body.text;
    if (typeof text !== 'string' || !text.trim()) return null;

    let dueAt: Date | null = null;
    if (typeof body.dueAt === 'string' && body.dueAt) {
        dueAt = parseDateISOString(body.dueAt);
        if (isNaN(dueAt.getTime())) {
            return null;
        }
    }

    const rrule: string | null = dueAt !== null && typeof body.rrule === 'string' && body.rrule ? body.rrule : null;

    const color = typeof body.color === 'string' && body.color ? body.color : null;

    const collaboratorIds: string[] = Array.isArray(body.collaboratorIds)
        ? body.collaboratorIds.filter((id: unknown) => typeof id === 'string')
        : [];

    const alerts: AlertInput[] = [];
    if (Array.isArray(body.alerts)) {
        for (const a of body.alerts) {
            if (a?.type === 'absolute' && typeof a.alertAt === 'string') {
                const d = new Date(a.alertAt);
                if (!isNaN(d.getTime())) alerts.push({ type: 'absolute', alertAt: d });
            } else if (a?.type === 'relative' && typeof a.timeBefore === 'string') {
                alerts.push({ type: 'relative', timeBefore: a.timeBefore });
            }
        }
    }

    return {
        text: text.trim(),
        rrule,
        color,
        collaboratorIds,
        alerts,
        dueAt: body.dueAt,
    };
}

const tasks = new Hono<{ Variables: AuthVariables }>();

tasks.use(requireAuth);

tasks.post('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);
    const parsed = await parseAlertsForm(body);

    if (!parsed) {
        return c.json({ error: 'text is required' }, 400);
    }

    let taskId: string;
    try {
        taskId = await editOrCreateTask(user.id, null, parsed);
    } catch (e) {
        console.error('[POST /api/tasks] createTask failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        return c.json({ error: message }, 500);
    }

    return c.json({ id: taskId }, 201);
});

// Edit task text, rrule, dueAt and collaborators
tasks.put('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);
    const parsed = await parseAlertsForm(body);

    if (!parsed) {
        return c.json({ error: 'text is required' }, 400);
    }

    if (typeof body.taskId !== 'string' || !body.taskId.trim()) {
        return c.json({ error: 'taskId is required' }, 400);
    }

    try {
        await editOrCreateTask(user.id, body.taskId, parsed);
    } catch (e) {
        console.error('[PUT /api/tasks] updateTask failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Task not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

// Mark task as done / undone
tasks.patch('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.taskId !== 'string' || !body.taskId.trim()) {
        return c.json({ error: 'taskId is required' }, 400);
    }
    if (typeof body.done !== 'boolean') {
        return c.json({ error: 'done (boolean) is required' }, 400);
    }

    let result: NextTaskInfo | null;
    try {
        result = await setTaskDone(user.id, body.taskId, body.done);
    } catch (e) {
        console.error('[PATCH /api/tasks] setTaskDone failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Task not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    if (result) {
        return c.json({ nextTaskId: result.nextTaskId, nextDueAt: result.nextDueAt.toISOString() }, 200);
    }
    return new Response(null, { status: 204 });
});

tasks.delete('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.taskId !== 'string' || !body.taskId.trim()) {
        return c.json({ error: 'taskId is required' }, 400);
    }

    try {
        await deleteTask(user.id, body.taskId);
    } catch (e) {
        console.error('[DELETE /api/tasks] deleteTask failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Task not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

export default tasks;
