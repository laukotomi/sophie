export type NoteFormData = {
    noteId: string;
    text: string;
    collaborators: CollaboratorInfo[] | undefined;
    fixedPosition: number | undefined;
    color: string | null;
    dontFold: boolean;
    todoList: boolean;
    files: NoteFile[] | undefined;
    timestamp: Date;
};

export type NoteFile = {
    id: string;
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
    taskId: string;
    text: string;
    rrule: string | null;
    color: string | null;
    dueAt: string;
    collaboratorIds: string[];
    alerts: AlertInput[];
    recurringGroupId: string | null;
    timestamp: Date;
}

export type AlertInput =
    | { type: 'absolute'; alertAt: Date }
    | { type: 'relative'; timeBefore: string };
