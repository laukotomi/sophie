export type NoteFormData = {
    text: string;
    collaborators: CollaboratorInfo[] | undefined;
    fixedPosition: number | undefined;
    color: string | null;
    dontFold: boolean;
    shoppingList: boolean;
    files: NoteFile[] | undefined;
};

export type NoteFile = {
    name: string;
    type: string;
    size: number;
    stream: ReadableStream<Uint8Array>;
}

export type CollaboratorInfo = {
    userId: string;
    right: 'view' | 'edit';
}

export type TaskData = {
    text: string;
    rrule: string | null;
    color: string | null;
    dueAt: string;
    collaboratorIds: string[];
    alerts: AlertInput[];
}

export type AlertInput =
    | { type: 'absolute'; alertAt: Date }
    | { type: 'relative'; timeBefore: string };
