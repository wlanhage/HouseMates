import { describe, it, expect } from 'vitest';
import { makeDb } from './helpers';
import { listEvents } from '../src/lib/server/events';

function insTimed(db: ReturnType<typeof makeDb>, id: string, start: string, end: string, title = id) {
  db.prepare(
    `INSERT INTO events (id, caldav_uid, title, all_day, start_ts, end_ts)
     VALUES (?, ?, ?, 0, ?, ?)`
  ).run(id, id, title, start, end);
}
function insAllDay(db: ReturnType<typeof makeDb>, id: string, sd: string, ed: string, title = id) {
  db.prepare(
    `INSERT INTO events (id, caldav_uid, title, all_day, start_date, end_date)
     VALUES (?, ?, ?, 1, ?, ?)`
  ).run(id, id, title, sd, ed);
}

describe('events – overlap-query (spec §15)', () => {
  it('tidsatt + heldag mot samma dag', () => {
    const db = makeDb();
    insTimed(db, 'timed', '2026-07-15T12:00:00.000Z', '2026-07-15T13:00:00.000Z');
    insAllDay(db, 'allday', '2026-07-15', '2026-07-16');
    insAllDay(db, 'multi', '2026-07-01', '2026-07-04'); // täcker 1,2,3

    const day15 = listEvents(db, '2026-07-15', '2026-07-15').map((e) => e.id).sort();
    expect(day15).toEqual(['allday', 'timed']);
  });

  it('flerdagars heldag syns för varje berörd dag men inte dagen efter slutet', () => {
    const db = makeDb();
    insAllDay(db, 'multi', '2026-07-01', '2026-07-04'); // exklusivt slut → 1,2,3

    expect(listEvents(db, '2026-07-01', '2026-07-01').map((e) => e.id)).toEqual(['multi']);
    expect(listEvents(db, '2026-07-03', '2026-07-03').map((e) => e.id)).toEqual(['multi']);
    expect(listEvents(db, '2026-07-04', '2026-07-04')).toHaveLength(0); // end_date exklusivt
  });

  it('raderade event exkluderas', () => {
    const db = makeDb();
    insTimed(db, 'gone', '2026-07-15T12:00:00.000Z', '2026-07-15T13:00:00.000Z');
    db.prepare("UPDATE events SET deleted_at = datetime('now') WHERE id = 'gone'").run();
    expect(listEvents(db, '2026-07-15', '2026-07-15')).toHaveLength(0);
  });

  it('normaliserar allDay + isRecurring korrekt', () => {
    const db = makeDb();
    insAllDay(db, 'a', '2026-07-15', '2026-07-16');
    db.prepare("UPDATE events SET recurrence_id = '2026-07-15' WHERE id = 'a'").run();
    const e = listEvents(db, '2026-07-15', '2026-07-15')[0];
    expect(e.allDay).toBe(true);
    expect(e.start).toBe('2026-07-15');
    expect(e.isRecurring).toBe(true);
  });
});
