import { serveStatic } from '@hono/node-server/serve-static';
import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { auth } from './auth.js';
import notesRouter from './routes/notes.js';
import dashboardRouter from './routes/dashboard.js';
import tasksRouter from './routes/tasks.js';
import tokenRouter from './routes/token.js';
import filesRouter from './routes/files.js';

export function createApp() {
    const app = new Hono();
    const webRoot = process.env.WEB_ROOT ?? 'web';
    const webIndexPath = join(process.cwd(), webRoot, 'index.html');
    const hasWebBuild = existsSync(webIndexPath);

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

    app.get('/healthz', (c) => c.json({ status: 'ok' }));

    if (hasWebBuild) {
        app.use('*', serveStatic({ root: `./${webRoot}` }));

        // SPA fallback for client-side routes.
        app.get('*', async (c) => {
            if (c.req.path.startsWith('/api/')) {
                return c.notFound();
            }

            const indexHtml = await readFile(webIndexPath, 'utf-8');
            c.header('Content-Type', 'text/html; charset=utf-8');
            return c.body(indexHtml);
        });
    } else {
        app.get('/', (c) => c.json({ status: 'ok' }));
    }

    return app;
}

export const app = createApp();