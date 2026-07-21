import { describe, it, expect } from 'vitest';
import { makeDb } from './helpers';
import * as shopping from '../src/lib/server/shopping';
import { HttpError } from '../src/lib/server/http';

describe('inköp – API-flöden (spec §15)', () => {
  it('dubblett (samma name_norm) → merge med befintlig vara', () => {
    const db = makeDb();
    const a = shopping.add(db, 'anna', { id: 'i1', name: 'Mjölk' });
    expect(a.merged).toBe(false);

    const b = shopping.add(db, 'erik', { id: 'i2', name: '  mjölk ' }); // annat id, samma norm
    expect(b.merged).toBe(true);
    expect(b.item.id).toBe('i1');
    expect(shopping.listActive(db)).toHaveLength(1);
  });

  it('idempotent POST med samma id → samma vara, ingen dubblett', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'Bröd' });
    const again = shopping.add(db, 'anna', { id: 'i1', name: 'Bröd' });
    expect(again.merged).toBe(false);
    expect(again.item.id).toBe('i1');
    expect(shopping.listActive(db)).toHaveLength(1);
  });

  it('optimistisk låsning → version_conflict med current', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'Ost' });
    shopping.patch(db, 'anna', 'i1', { version: 1, checked: true }); // → version 2

    let err: HttpError | null = null;
    try {
      shopping.patch(db, 'erik', 'i1', { version: 1, checked: false }); // gammal version
    } catch (e) {
      err = e as HttpError;
    }
    expect(err).toBeInstanceOf(HttpError);
    expect(err!.code).toBe('version_conflict');
    expect((err!.extra.current as { version: number }).version).toBe(2);
  });

  it('bocka av ökar version och sätter checked_by', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'Smör' });
    const updated = shopping.patch(db, 'erik', 'i1', { version: 1, checked: true });
    expect(updated.checked).toBe(true);
    expect(updated.checked_by).toBe('erik');
    expect(updated.version).toBe(2);
  });

  it('restore med dubblettkrock → duplicate', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'Salt' });
    shopping.remove(db, 'anna', 'i1'); // soft delete
    shopping.add(db, 'anna', { id: 'i2', name: 'Salt' }); // ny aktiv med samma norm

    let err: HttpError | null = null;
    try {
      shopping.restore(db, 'anna', 'i1');
    } catch (e) {
      err = e as HttpError;
    }
    expect(err).toBeInstanceOf(HttpError);
    expect(err!.code).toBe('duplicate');
  });

  it('archive-checked arkiverar avbockade och loggar EN rad', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'A' });
    shopping.add(db, 'anna', { id: 'i2', name: 'B' });
    shopping.patch(db, 'anna', 'i1', { version: 1, checked: true });

    const res = shopping.archiveChecked(db, 'anna');
    expect(res.count).toBe(1);
    expect(res.ids).toEqual(['i1']);
    expect(shopping.listActive(db)).toHaveLength(1); // bara B kvar

    const acts = db
      .prepare("SELECT * FROM activity_log WHERE type = 'shopping.archived'")
      .all() as { payload: string }[];
    expect(acts).toHaveLength(1);
    expect(JSON.parse(acts[0].payload).count).toBe(1);
  });

  it('unarchive återställer arkiverade varor', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'A' });
    shopping.patch(db, 'anna', 'i1', { version: 1, checked: true });
    const { ids } = shopping.archiveChecked(db, 'anna');
    const res = shopping.unarchive(db, 'anna', ids);
    expect(res.restored).toBe(1);
  });

  it('varje mutation köar en notis till partnern', () => {
    const db = makeDb();
    shopping.add(db, 'anna', { id: 'i1', name: 'Te' });
    const q = db
      .prepare('SELECT recipient FROM notification_queue')
      .all() as { recipient: string }[];
    expect(q).toHaveLength(1);
    expect(q[0].recipient).toBe('erik'); // partnern, inte aktören
  });
});
