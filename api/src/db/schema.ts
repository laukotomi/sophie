import { pgTable, pgEnum, serial, integer, boolean, text, timestamp, time, uniqueIndex } from 'drizzle-orm/pg-core';
import { sql } from 'drizzle-orm';
import { user } from './auth.schema.js';

export const noteRight = pgEnum('note_right', ['view', 'edit']);

export const note = pgTable('note', {
    id: text('id').primaryKey(),
    text: text('text').notNull(),
    color: text('color'),
    dontFold: boolean('dont_fold').notNull().default(false),
    todoList: boolean('todo_list').notNull().default(false),
    owner: text('owner')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow().$onUpdate(() => new Date()),
    editingBy: text('editing_by').references(() => user.id, { onDelete: 'set null' }),
    lockedUntil: timestamp('locked_until', { withTimezone: true }),
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

export const noteHistory = pgTable('note_history', {
    id: serial('id').primaryKey(),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    text: text('text').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
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

export const noteFiles = pgTable('note_files', {
    id: text('id').primaryKey(),
    noteId: text('note_id')
        .notNull()
        .references(() => note.id, { onDelete: 'cascade' }),
    fileName: text('file_name').notNull(),
    fileType: text('file_type').notNull(),
    fileSize: integer('file_size').notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const task = pgTable('task', {
    id: text('id').primaryKey(),
    owner: text('owner')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    text: text('text').notNull(),
    rrule: text('rrule'),
    color: text('color'),
    dueAt: timestamp('due_at', { mode: 'string' }),
    doneAt: timestamp('done_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

export const taskCollaborator = pgTable('task_collaborator', {
    id: serial('id').primaryKey(),
    userId: text('user_id')
        .notNull()
        .references(() => user.id, { onDelete: 'cascade' }),
    taskId: text('task_id')
        .notNull()
        .references(() => task.id, { onDelete: 'cascade' }),
}, (t) => [
    uniqueIndex('task_collaborator_user_id_task_id_idx').on(t.userId, t.taskId),
]);

// An alert can be either:
//   alertAt   — fire at an absolute date+time
//   timeBefore — fire X hours and Y minutes before the task's dueAt (stored as HH:MM:SS)
// Exactly one of the two should be set.
export const taskAlert = pgTable('task_alert', {
    id: serial('id').primaryKey(),
    taskId: text('task_id')
        .notNull()
        .references(() => task.id, { onDelete: 'cascade' }),
    alertAt: timestamp('alert_at', { withTimezone: true }),
    timeBefore: time('time_before'),
});

export * from './auth.schema.js';
