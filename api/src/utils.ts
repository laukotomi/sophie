import { join } from 'node:path';

export function parseDateISOString(s: string) {
    let ds = s.split(/\D/).map(s => parseInt(s));
    ds[1] = ds[1] - 1; // adjust month
    return new Date(ds[0], ds[1], ds[2], ds[3], ds[4], ds[5]);
}

export function uploadsDir(): string {
    return process.env.UPLOADS_DIR ?? './uploads';
}

export function noteFilePath(noteId: string, fileId: string): string {
    return join(uploadsDir(), noteId, fileId);
}

export function noteDirPath(noteId: string): string {
    return join(uploadsDir(), noteId);
}
