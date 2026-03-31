import { betterAuth } from 'better-auth/minimal';
import { drizzleAdapter } from 'better-auth/adapters/drizzle';
import { bearer } from 'better-auth/plugins';
import { db } from './db/index.js';

if (!process.env.BETTER_AUTH_SECRET) throw new Error('BETTER_AUTH_SECRET is not set');
if (!process.env.ORIGIN) throw new Error('ORIGIN is not set');

export const auth = betterAuth({
    baseURL: process.env.ORIGIN,
    secret: process.env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(db, { provider: 'pg' }),
    emailAndPassword: { enabled: true },
    session: {
        expiresIn: 60 * 60 * 24 * 365, // 1 year for long-lived mobile tokens
    },
    plugins: [bearer()],
});
