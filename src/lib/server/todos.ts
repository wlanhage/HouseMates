/**
 * Att göra – tjänstelager (spec §7.4). Funktionerna tar `db` (testbara).
 */
import type { Database } from 'better-sqlite3';
import { now, toIso } from './sqlite-util';
import { HttpError } from './http';
import { logActivity } from './activity';
import type { Todo } from '$lib/types';

interface Row {
  id: string;
  title: string;
  notes: string | null;
  assignee: string | null;
  start_date: string | null;
  due_date: string | null;
  done: number;
  done_by: string | null;
  done_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  version: number;
  deleted_at: string | null;
}

function toTodo(r: Row): Todo {
  return {
    id: r.id,
    title: r.title,
    notes: r.notes,
    assignee: r.assignee,
    start_date: r.start_date,
    due_date: r.due_date,
    done: r.done === 1,
    done_by: r.done_by,
    done_at: toIso(r.done_at),
    created_by: r.created_by,
    created_at: toIso(r.created_at)!,
    updated_at: toIso(r.updated_at)!,
    version: r.version
  };
}

const byId = (db: Database, id: string): Row | undefined =>
  db.prepare('SELECT * FROM todos WHERE id = ?').get(id) as Row | undefined;

function validateAssignee(db: Database, assignee: string | null | undefined): string | null {
  if (assignee == null || assignee === 'both') return assignee ?? null;
  const u = db.prepare('SELECT 1 FROM users WHERE id = ?').get(assignee);
  if (!u) throw new HttpError('validation', 'Ogiltig ansvarig.', 400);
  return assignee;
}

/** Period kräver deadline och start <= deadline. */
function validatePeriod(start: string | null, due: string | null): void {
  if (start && !due) {
    throw new HttpError('validation', 'En period kräver en deadline.', 400);
  }
  if (start && due && start > due) {
    throw new HttpError('validation', 'Startdatum måste vara före deadline.', 400);
  }
}

/** filter=open: deadline-satta först (stigande), sedan created_at fallande. */
export function listOpen(db: Database): Todo[] {
  const rows = db
    .prepare(
      `SELECT * FROM todos
       WHERE done = 0 AND deleted_at IS NULL
       ORDER BY (due_date IS NULL), due_date ASC, created_at DESC`
    )
    .all() as Row[];
  return rows.map(toTodo);
}

/** filter=done: done_at fallande, max 30 dagar. */
export function listDone(db: Database): Todo[] {
  const rows = db
    .prepare(
      `SELECT * FROM todos
       WHERE done = 1 AND deleted_at IS NULL AND done_at >= datetime('now', '-30 days')
       ORDER BY done_at DESC`
    )
    .all() as Row[];
  return rows.map(toTodo);
}

export function add(
  db: Database,
  actor: string,
  input: {
    id: string;
    title: string;
    notes?: string | null;
    assignee?: string | null;
    start_date?: string | null;
    due_date?: string | null;
  }
): Todo {
  const title = input.title.trim();
  if (!title) throw new HttpError('validation', 'Titel krävs.', 400);

  const existing = byId(db, input.id);
  if (existing) return toTodo(existing);

  const assignee = validateAssignee(db, input.assignee);
  validatePeriod(input.start_date ?? null, input.due_date ?? null);
  db.prepare(
    'INSERT INTO todos (id, title, notes, assignee, start_date, due_date, created_by) VALUES (?, ?, ?, ?, ?, ?, ?)'
  ).run(
    input.id,
    title,
    input.notes ?? null,
    assignee,
    input.start_date ?? null,
    input.due_date ?? null,
    actor
  );

  logActivity(db, {
    type: 'todo.created',
    actor,
    entityType: 'todo',
    entityId: input.id,
    payload: { title }
  });
  return toTodo(byId(db, input.id)!);
}

export function patch(
  db: Database,
  actor: string,
  id: string,
  input: {
    version: number;
    done?: boolean;
    title?: string;
    notes?: string | null;
    assignee?: string | null;
    start_date?: string | null;
    due_date?: string | null;
  }
): Todo {
  const row = byId(db, id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Uppgiften finns inte.', 404);
  if (input.version !== row.version) {
    throw new HttpError('version_conflict', 'Uppdaterades av någon annan.', 409, {
      current: toTodo(row)
    });
  }

  let title = row.title;
  let notes = row.notes;
  let assignee = row.assignee;
  let start = row.start_date;
  let due = row.due_date;
  let done = row.done;
  let doneBy = row.done_by;
  let doneAt = row.done_at;
  let toggled: 'done' | 'undone' | null = null;

  if (input.title !== undefined) {
    title = input.title.trim();
    if (!title) throw new HttpError('validation', 'Titel krävs.', 400);
  }
  if (input.notes !== undefined) notes = input.notes;
  if (input.assignee !== undefined) assignee = validateAssignee(db, input.assignee);
  if (input.start_date !== undefined) start = input.start_date;
  if (input.due_date !== undefined) due = input.due_date;
  validatePeriod(start, due);
  if (input.done !== undefined && input.done !== (row.done === 1)) {
    if (input.done) {
      done = 1;
      doneBy = actor;
      doneAt = now();
      toggled = 'done';
    } else {
      done = 0;
      doneBy = null;
      doneAt = null;
      toggled = 'undone';
    }
  }

  db.prepare(
    `UPDATE todos
     SET title = ?, notes = ?, assignee = ?, start_date = ?, due_date = ?, done = ?, done_by = ?, done_at = ?,
         updated_at = ?, version = version + 1
     WHERE id = ?`
  ).run(title, notes, assignee, start, due, done, doneBy, doneAt, now(), id);

  if (toggled) {
    logActivity(db, {
      type: toggled === 'done' ? 'todo.done' : 'todo.undone',
      actor,
      entityType: 'todo',
      entityId: id,
      payload: { title }
    });
  }
  return toTodo(byId(db, id)!);
}

export function remove(db: Database, actor: string, id: string): { title: string } {
  const row = byId(db, id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Uppgiften finns inte.', 404);
  db.prepare('UPDATE todos SET deleted_at = ?, deleted_by = ?, updated_at = ? WHERE id = ?').run(
    now(),
    actor,
    now(),
    id
  );
  logActivity(db, {
    type: 'todo.deleted',
    actor,
    entityType: 'todo',
    entityId: id,
    payload: { title: row.title }
  });
  return { title: row.title };
}

export function restore(db: Database, actor: string, id: string): Todo {
  const row = byId(db, id);
  if (!row) throw new HttpError('not_found', 'Uppgiften finns inte.', 404);
  db.prepare('UPDATE todos SET deleted_at = NULL, deleted_by = NULL, updated_at = ? WHERE id = ?').run(
    now(),
    id
  );
  logActivity(db, {
    type: 'todo.restored',
    actor,
    entityType: 'todo',
    entityId: id,
    payload: { title: row.title }
  });
  return toTodo(byId(db, id)!);
}
