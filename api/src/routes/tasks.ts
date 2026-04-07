import { Hono } from 'hono';
import { requireAuth, type AuthVariables } from '../middleware.js';
import { createTask, deleteTask, updateTask, setTaskDone } from '../task_queries.js';

const tasks = new Hono<{ Variables: AuthVariables }>();

tasks.use(requireAuth);

tasks.post('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.text !== 'string' || !body.text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    const rrule = typeof body.rrule === 'string' && body.rrule ? body.rrule : null;

    let dueAt: Date | null = null;
    if (typeof body.dueAt === 'string' && body.dueAt) {
        dueAt = new Date(body.dueAt);
        if (isNaN(dueAt.getTime())) {
            return c.json({ error: 'dueAt is not a valid date' }, 400);
        }
    }

    const color = typeof body.color === 'string' && body.color ? body.color : null;

    const collaboratorIds: string[] = Array.isArray(body.collaboratorIds)
        ? body.collaboratorIds.filter((id: unknown) => typeof id === 'string')
        : [];

    type AlertInput =
        | { type: 'absolute'; alertAt: Date }
        | { type: 'relative'; timeBefore: string };

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

    try {
        await createTask(user.id, body.text.trim(), rrule, dueAt, color, collaboratorIds, alerts);
    } catch (e) {
        console.error('[POST /api/tasks] createTask failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 201 });
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

// Edit task text, rrule, dueAt and collaborators
tasks.put('/', async (c) => {
    const user = c.get('user');
    const body = await c.req.json().catch(() => null);

    if (!body || typeof body.taskId !== 'string' || !body.taskId.trim()) {
        return c.json({ error: 'taskId is required' }, 400);
    }
    if (typeof body.text !== 'string' || !body.text.trim()) {
        return c.json({ error: 'text is required' }, 400);
    }

    const rrule = typeof body.rrule === 'string' && body.rrule ? body.rrule : null;

    let dueAt: Date | null = null;
    if (typeof body.dueAt === 'string' && body.dueAt) {
        dueAt = new Date(body.dueAt);
        if (isNaN(dueAt.getTime())) {
            return c.json({ error: 'dueAt is not a valid date' }, 400);
        }
    }

    const color = typeof body.color === 'string' && body.color ? body.color : null;

    const collaboratorIds: string[] = Array.isArray(body.collaboratorIds)
        ? body.collaboratorIds.filter((id: unknown) => typeof id === 'string')
        : [];

    type AlertInput =
        | { type: 'absolute'; alertAt: Date }
        | { type: 'relative'; timeBefore: string };

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

    try {
        await updateTask(user.id, body.taskId, body.text.trim(), rrule, dueAt, color, collaboratorIds, alerts);
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

    try {
        await setTaskDone(user.id, body.taskId, body.done);
    } catch (e) {
        console.error('[PATCH /api/tasks] setTaskDone failed:', e);
        const message = e instanceof Error ? e.message : 'Unknown error';
        if (message === 'Task not found') return c.json({ error: message }, 404);
        if (message === 'Forbidden') return c.json({ error: message }, 403);
        return c.json({ error: message }, 500);
    }

    return new Response(null, { status: 204 });
});

export default tasks;
