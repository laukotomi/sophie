import { join } from 'node:path';

export function uploadsDir(): string {
    return process.env.UPLOADS_DIR ?? './uploads';
}

export function noteFilePath(noteId: string, fileId: string): string {
    return join(uploadsDir(), noteId, fileId);
}

export function noteDirPath(noteId: string): string {
    return join(uploadsDir(), noteId);
}
