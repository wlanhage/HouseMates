import { describe, it, expect } from 'vitest';
import { makeDb } from './helpers';
import * as todos from '../src/lib/server/todos';
import { HttpError } from '../src/lib/server/http';

describe('att göra – API-flöden', () => {
  it('idempotent POST med samma id', () => {
    const db = makeDb();
    todos.add(db, 'anna', { id: 't1', title: 'Diska' });
    todos.add(db, 'anna', { id: 't1', title: 'Diska' });
    expect(todos.listOpen(db)).toHaveLength(1);
  });

  it('klarmarkering sätter done_by/done_at och flyttar till done-listan', () => {
    const db = makeDb();
    todos.add(db, 'anna', { id: 't1', title: 'Handla' });
    const done = todos.patch(db, 'erik', 't1', { version: 1, done: true });
    expect(done.done).toBe(true);
    expect(done.done_by).toBe('erik');
    expect(todos.listOpen(db)).toHaveLength(0);
    expect(todos.listDone(db)).toHaveLength(1);
  });

  it('version_conflict vid gammal version', () => {
    const db = makeDb();
    todos.add(db, 'anna', { id: 't1', title: 'Städa' });
    todos.patch(db, 'anna', 't1', { version: 1, done: true });
    let err: HttpError | null = null;
    try {
      todos.patch(db, 'erik', 't1', { version: 1, done: false });
    } catch (e) {
      err = e as HttpError;
    }
    expect(err?.code).toBe('version_conflict');
  });

  it('öppna sorteras: deadline först (stigande), sedan nyast', () => {
    const db = makeDb();
    todos.add(db, 'anna', { id: 't1', title: 'Ingen deadline' });
    todos.add(db, 'anna', { id: 't2', title: 'Sen', due_date: '2026-12-31' });
    todos.add(db, 'anna', { id: 't3', title: 'Tidig', due_date: '2026-01-01' });
    const open = todos.listOpen(db);
    expect(open.map((t) => t.id)).toEqual(['t3', 't2', 't1']);
  });

  it('ogiltig ansvarig → validation', () => {
    const db = makeDb();
    let err: HttpError | null = null;
    try {
      todos.add(db, 'anna', { id: 't1', title: 'X', assignee: 'finns-ej' });
    } catch (e) {
      err = e as HttpError;
    }
    expect(err?.code).toBe('validation');
  });

  it('assignee "both" tillåts', () => {
    const db = makeDb();
    const t = todos.add(db, 'anna', { id: 't1', title: 'Gemensam', assignee: 'both' });
    expect(t.assignee).toBe('both');
  });

  it('period (start_date + due_date) sparas', () => {
    const db = makeDb();
    const t = todos.add(db, 'anna', {
      id: 't1',
      title: 'Måla om',
      start_date: '2026-07-20',
      due_date: '2026-07-27'
    });
    expect(t.start_date).toBe('2026-07-20');
    expect(t.due_date).toBe('2026-07-27');
  });

  it('period utan deadline → validation', () => {
    const db = makeDb();
    let err: HttpError | null = null;
    try {
      todos.add(db, 'anna', { id: 't1', title: 'X', start_date: '2026-07-20' });
    } catch (e) {
      err = e as HttpError;
    }
    expect(err?.code).toBe('validation');
  });

  it('start efter deadline → validation', () => {
    const db = makeDb();
    let err: HttpError | null = null;
    try {
      todos.add(db, 'anna', {
        id: 't1',
        title: 'X',
        start_date: '2026-07-28',
        due_date: '2026-07-27'
      });
    } catch (e) {
      err = e as HttpError;
    }
    expect(err?.code).toBe('validation');
  });

  it('patch kan sätta och rensa period', () => {
    const db = makeDb();
    todos.add(db, 'anna', { id: 't1', title: 'X', due_date: '2026-07-27' });
    const withStart = todos.patch(db, 'anna', 't1', { version: 1, start_date: '2026-07-20' });
    expect(withStart.start_date).toBe('2026-07-20');
    const cleared = todos.patch(db, 'anna', 't1', { version: 2, start_date: null });
    expect(cleared.start_date).toBeNull();
  });
});
