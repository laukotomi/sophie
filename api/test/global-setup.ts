import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { PostgreSqlContainer } from '@testcontainers/postgresql';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const apiRoot = resolve(__dirname, '..');

export default async function globalSetup() {
    const container = await new PostgreSqlContainer('postgres:16-alpine').start();

    process.env.DATABASE_URL = container.getConnectionUri();
    process.env.BETTER_AUTH_SECRET ??= 'integration-test-secret';
    process.env.ORIGIN ??= 'http://localhost';
    process.env.CORS_ORIGIN ??= '*';

    execSync('npm run db:migrate', {
        cwd: apiRoot,
        stdio: 'inherit',
        env: process.env,
    });

    return async () => {
        await container.stop();
    };
}