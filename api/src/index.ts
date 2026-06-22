import { serve } from '@hono/node-server';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { auth } from './auth.js';
import notesRouter from './routes/notes.js';
import dashboardRouter from './routes/dashboard.js';
import tasksRouter from './routes/tasks.js';
import tokenRouter from './routes/token.js';
import filesRouter from './routes/files.js';

const app = new Hono();

app.use(cors({
    origin: process.env.CORS_ORIGIN ?? '*',
    allowHeaders: ['Content-Type', 'Authorization'],
    allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));

app.use(async (c, next) => {
    const start = performance.now();
    await next();
    const ms = (performance.now() - start).toFixed(1);
    console.log(`${c.req.method} ${new URL(c.req.url).pathname} ${c.res.status} ${ms}ms`);
});

app.onError((err, c) => {
    console.error(`[${c.req.method}] ${c.req.url}`, err);
    return c.json({ error: 'Internal server error' }, 500);
});

// Mount better-auth's built-in routes (sign-up, sign-out, session, etc.)
app.on(['GET', 'POST'], '/api/auth/**', (c) => auth.handler(c.req.raw));

// Application routes
app.route('/api/token', tokenRouter);
app.route('/api/dashboard', dashboardRouter);
app.route('/api/notes', notesRouter);
app.route('/api/tasks', tasksRouter);
app.route('/api/files', filesRouter);

app.get('/', (c) => c.json({ status: 'ok' }));

const port = Number(process.env.PORT ?? 3000);
console.log(`Server running on http://localhost:${port}`);

const server = serve({ fetch: app.fetch, port });

process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
});
