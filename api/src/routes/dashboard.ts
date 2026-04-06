import { Hono } from 'hono';
import { getDashboardData } from '../note_queries.js';
import { requireAuth, type AuthVariables } from '../middleware.js';

const dashboard = new Hono<{ Variables: AuthVariables }>();

dashboard.use(requireAuth);

dashboard.get('/', async (c) => {
    const user = c.get('user');
    const data = await getDashboardData(user.id);
    return c.json({ user, ...data });
});

export default dashboard;
