import postgres from 'postgres';
import type { User } from './models';

let sql: postgres.Sql | null = null;
let appFetch: ((request: Request) => Response | Promise<Response>) | null = null;

export const TEST_USER1: User = {
    id: '', // will be set after registration
    email: 'test1@example.com',
    password: 'password',
    name: 'Test User 1',
};

export const TEST_USER2: User = {
    id: '', // will be set after registration
    email: 'test2@example.com',
    password: 'password',
    name: 'Test User 2',
};

export async function ensureTestEnv() {
    if (sql && appFetch) return;

    if (!process.env.DATABASE_URL) {
        throw new Error('DATABASE_URL is missing. Ensure global setup has run.');
    }

    process.env.BETTER_AUTH_SECRET ??= 'integration-test-secret';
    process.env.ORIGIN ??= 'http://localhost';
    process.env.CORS_ORIGIN ??= '*';

    sql = postgres(process.env.DATABASE_URL, { max: 1 });

    // Import after env vars are set, since auth/db modules validate env at import-time.
    const appModule = await import('../src/app.js');
    appFetch = appModule.app.fetch;
}

export async function resetDatabase() {
    if (!sql) throw new Error('Test DB is not initialized. Call ensureTestEnv first.');

    const tables = await sql<{ tablename: string }[]>`
        select tablename
        from pg_tables
        where schemaname = 'public'
    `;

    const tableNames = tables
        .map((t) => t.tablename)
        .filter((name) => name !== '__drizzle_migrations');

    if (tableNames.length === 0) return;

    const quoted = tableNames
        .map((name) => `"${name.replaceAll('"', '""')}"`)
        .join(', ');

    await sql.unsafe(`TRUNCATE TABLE ${quoted} RESTART IDENTITY CASCADE`);
    await registerTestUser(TEST_USER1);
    await registerTestUser(TEST_USER2);
}

export async function stopTestEnv() {
    if (sql) {
        await sql.end({ timeout: 5 });
        sql = null;
    }

    appFetch = null;
}

export async function request(path: string, init?: RequestInit) {
    if (!appFetch) throw new Error('App is not initialized. Call ensureTestEnv first.');

    const req = new Request(`http://localhost${path}`, init);
    return appFetch(req);
}

export type JsonRequest = {
    token?: string;
    method: string;
    body?: any;
    others?: RequestInit;
}

export async function requestJson(path: string, data: JsonRequest) {
    const res = await request(path, {
        method: data.method,
        headers: {
            'content-type': 'application/json',
            ...(data.token ? { 'authorization': `Bearer ${data.token}` } : {}),
            ...data.others?.headers
        },
        body: JSON.stringify(data.body),
        ...data.others,
    });
    return res;
}

export async function registerTestUser(user: User) {
    const res = await request('/api/auth/sign-up/email', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(user),
    });

    const text = await res.text();

    if (res.ok) {
        const data = JSON.parse(text);
        user.id = data.user.id;
        return;
    }

    const knownAlreadyExists =
        res.status === 409 ||
        text.toLowerCase().includes('already exists');

    if (!knownAlreadyExists) {
        throw new Error(`Failed to register test user: ${res.status} ${text}`);
    }
}

export async function loginTestUser(user: User) {
    const res = await request('/api/token', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
            email: user.email,
            password: user.password,
        }),
    });

    if (!res.ok) {
        throw new Error(`Failed to login test user: ${res.status} ${await res.text()}`);
    }

    const body = await res.json() as { token?: string };
    if (!body.token) {
        throw new Error('Token endpoint returned no bearer token');
    }

    return body.token;
}
