import { serve } from '@hono/node-server';
import { app } from './app.js';

const port = Number(process.env.PORT ?? 3000);
console.log(`Server running on http://localhost:${port}`);

const server = serve({ fetch: app.fetch, port });

process.on('SIGTERM', () => {
    server.close(() => process.exit(0));
});
