import { pgTable, pgEnum, serial, integer, text, timestamp, uniqueIndex } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
import { user } from './auth.schema.js';

export const noteRight = pgEnum('note_right', ['view', 'edit']);

export const note = pgTable('note', {
    id: text('id').primaryKey().default(sql`gen_random_uuid()`),
    text: text('text').notNull(),
    owner: text('owner')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at').notNull().defaultNow(),
    updatedAt: timestamp('updated_at').notNull().defaultNow().$onUpdate(() => new Date()),
});

export const collaborator = pgTable('collaborator', {
    id: serial('id').primaryKey(),
    userId: text('user_id')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    right: noteRight('right').notNull(),
}, (t) => [
    uniqueIndex('collaborator_user_id_note_id_idx').on(t.userId, t.noteId),
]);

export const alert = pgTable('alert', {
    id: serial('id').primaryKey(),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    time: text('time').notNull(),
});

export const noteHistory = pgTable('note_history', {
    id: serial('id').primaryKey(),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    text: text('text').notNull(),
    createdAt: timestamp('created_at').notNull().defaultNow(),
});

export const noteOrder = pgTable('note_order', {
    userId: text('user_id')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    position: integer('position').notNull(),
}, (t) => [
    uniqueIndex('note_order_user_id_note_id_idx').on(t.userId, t.noteId),
]);

export * from './auth.schema.js';
