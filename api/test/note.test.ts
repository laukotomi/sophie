import { describe, it, expect } from "vitest";
import { loginTestUser, request, requestJson, TEST_USER1, TEST_USER2 } from "./harness";
import { NoteFormData } from "../src/models";
import { randomUUID } from "crypto";
import { count, eq } from "drizzle-orm";
import { db } from "../src/db";
import { note as noteTable } from "../src/db/schema";


describe('Note API integration', () => {
    it('can delete a non-existent note without error', async () => {
        const token = await loginTestUser(TEST_USER1);
        const res = await requestJson('/api/notes', {
            method: 'DELETE',
            token: token,
            body: { noteId: 'non-existent-note-id' },
        });

        expect(res.status).toBe(204);
    });

    it('can create a note', async () => {
        const token = await loginTestUser(TEST_USER1);
        await createNoteForUser(token);
    });

    it('cannot delete a note that belongs to another user', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const note = await createNoteForUser(token1);

        const res = await requestJson('/api/notes', {
            token: token2,
            method: 'DELETE',
            body: { noteId: note.noteId },
        });

        expect(res.status).toBe(403);
    });

    it('can delete its own note', async () => {
        const token = await loginTestUser(TEST_USER1);
        const note = await createNoteForUser(token);

        const res = await requestJson('/api/notes', {
            token: token,
            method: 'DELETE',
            body: { noteId: note.noteId },
        });

        expect(res.status).toBe(204);

        const [{ count: noteCount }] = await db
            .select({ count: count() })
            .from(noteTable)
            .where(eq(noteTable.id, note.noteId));

        expect(noteCount).toBe(0);
    });

    it('can create a task multiple times with the same taskId', async () => {
        const token = await loginTestUser(TEST_USER1);
        const noteId = randomUUID();

        const timestamp = new Date();
        await createNoteForUser(token, { noteId, timestamp });
        await createNoteForUser(token, { noteId, text: 'updated text', timestamp });
    });

    it('cannot acquire lock if another user has it', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const note = await createNoteForUser(token1, {
            collaborators: [{
                right: 'edit',
                userId: TEST_USER2.id,
            }]
        });

        // Acquire lock for user 1
        await testAcquireLock(token1, note.noteId, 200);

        // Attempt to acquire lock for user 2
        await testAcquireLock(token2, note.noteId, 423);
    });

    it('cannot acquire lock if cannot edit the note', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const note = await createNoteForUser(token1, {
            collaborators: [{
                right: 'view',
                userId: TEST_USER2.id,
            }]
        });

        await testAcquireLock(token2, note.noteId, 403);
    });

    it('can acquire lock multiple times', async () => {
        const token = await loginTestUser(TEST_USER1);
        const note = await createNoteForUser(token);

        // Acquire lock
        await testAcquireLock(token, note.noteId, 200);

        // Acquire lock again
        await testAcquireLock(token, note.noteId, 200);
    });

    it('can release lock', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const note = await createNoteForUser(token1, {
            collaborators: [{
                right: 'edit',
                userId: TEST_USER2.id,
            }]
        });

        // Acquire lock for user 1
        await testAcquireLock(token1, note.noteId, 200);

        // Release lock for user 1
        const res = await requestJson('/api/notes/edit', {
            token: token1,
            method: 'DELETE',
            body: { noteId: note.noteId },
        });

        expect(res.status).toBe(204);

        // Attempt to acquire lock for user 2
        await testAcquireLock(token2, note.noteId, 200);
    });

    it('can refresh lock', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const note = await createNoteForUser(token1);

        await testAcquireLock(token1, note.noteId, 200);

        const res = await requestJson('/api/notes/edit', {
            token: token1,
            method: 'POST',
            body: { noteId: note.noteId },
        });

        expect(res.status).toBe(200);
    });

    it('cannot refresh lock if another user has it', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);
        const note = await createNoteForUser(token1, {
            collaborators: [{
                right: 'edit',
                userId: TEST_USER2.id,
            }]
        });

        // Acquire lock for user 1
        await testAcquireLock(token1, note.noteId, 200);

        // Attempt to refresh lock for user 2
        const res = await requestJson('/api/notes/edit', {
            token: token2,
            method: 'POST',
            body: { noteId: note.noteId },
        });

        expect(res.status).toBe(423);
    });

    it('can edit with lock', async () => {
        const token = await loginTestUser(TEST_USER1);
        const noteId = randomUUID();
        const note = await createNoteForUser(token, {
            noteId,
        });

        // Acquire lock
        await testAcquireLock(token, note.noteId, 200);

        // Edit note
        await createNoteForUser(token, {
            noteId: note.noteId,
            text: 'Updated text',
            timestamp: note.timestamp
        });
    });

    it('cannot edit when another user has the lock', async () => {
        const token1 = await loginTestUser(TEST_USER1);
        const token2 = await loginTestUser(TEST_USER2);

        const noteId = randomUUID();
        const note = await createNoteForUser(token1, {
            noteId,
            collaborators: [{
                right: 'edit',
                userId: TEST_USER2.id,
            }]
        });

        await testAcquireLock(token1, note.noteId, 200);
        await createNoteForUser(token2, {
            noteId: note.noteId,
            text: 'Updated text',
            timestamp: note.timestamp
        }, 409);
    });
});

async function createNoteForUser(token: string, noteData?: Partial<NoteFormData>, expectStatus: number = 201) {
    const note: NoteFormData = {
        collaborators: [],
        color: null,
        dontFold: false,
        fixedPosition: undefined,
        files: [],
        noteId: randomUUID(),
        text: 'Test note content',
        timestamp: new Date(),
        todoList: false,
        ...noteData
    };

    const form = new FormData();
    form.set('noteId', note.noteId);
    form.set('text', note.text);
    form.set('collaborators', JSON.stringify(note.collaborators));
    form.set('dontFold', String(note.dontFold));
    form.set('todoList', String(note.todoList));
    form.set('timestamp', note.timestamp.toISOString());
    if (note.color !== null) form.set('color', note.color);
    if (note.fixedPosition !== undefined) form.set('fixedPosition', String(note.fixedPosition));

    const res = await request('/api/notes', {
        method: 'POST',
        headers: {
            'authorization': `Bearer ${token}`,
        },
        body: form,
    });

    expect(res.status).toBe(expectStatus);

    if (expectStatus > 299)
        return note;

    const [insertedNote] = await db
        .select()
        .from(noteTable)
        .where(eq(noteTable.id, note.noteId))
        .limit(1);

    expect(insertedNote).toBeDefined();

    expect(insertedNote!.id).toBe(note.noteId);
    expect(insertedNote!.text).toBe(note.text);
    expect(insertedNote!.color).toBe(note.color);
    expect(insertedNote!.dontFold).toBe(note.dontFold);
    expect(insertedNote!.todoList).toBe(note.todoList);
    expect(new Date(insertedNote!.createdAt).toISOString()).toBe(note.timestamp.toISOString());

    return note;
}

async function testAcquireLock(token: string, noteId: string, expectStatus: number) {
    const res2 = await requestJson('/api/notes/edit', {
        token: token,
        method: 'POST',
        body: { noteId: noteId },
    });

    expect(res2.status).toBe(expectStatus);
}