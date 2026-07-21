/**
 * Läsning av kalender-cachen (spec §7.5). Overlap-query enligt schema.sql:
 *   tidsatta:  start_ts < D_slut  AND end_ts > D_start
 *   heldagar:  start_date <= D    AND end_date > D
 * Vi frågar med lite marginal i UTC och låter frontend bucketera per lokal dag.
 * Ren modul (tar db) → testbar (§15).
 */
import type { Database } from 'better-sqlite3';
import type { CalendarEvent } from '$lib/types';

interface Row {
  id: string;
  recurrence_id: string;
  title: string;
  location: string | null;
  notes: string | null;
  all_day: number;
  start_ts: string | null;
  end_ts: string | null;
  start_date: string | null;
  end_date: string | null;
  created_by: string | null;
}

function addDaysStr(dateStr: string, n: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + n));
  const p = (x: number) => String(x).padStart(2, '0');
  return `${dt.getUTCFullYear()}-${p(dt.getUTCMonth() + 1)}-${p(dt.getUTCDate())}`;
}

function normalize(r: Row): CalendarEvent {
  const allDay = r.all_day === 1;
  return {
    id: r.id,
    title: r.title,
    allDay,
    start: (allDay ? r.start_date : r.start_ts)!,
    end: (allDay ? r.end_date : r.end_ts)!,
    location: r.location,
    notes: r.notes,
    createdBy: r.created_by,
    isRecurring: r.recurrence_id !== ''
  };
}

/** Events som överlappar dagsintervallet [from, to] (inklusive). */
export function listEvents(db: Database, from: string, to: string): CalendarEvent[] {
  // UTC-marginal ±1 dygn så tidsatta event nära lokala dygnsgränser kommer med.
  const fromUtc = addDaysStr(from, -1) + 'T00:00:00.000Z';
  const toUtc = addDaysStr(to, 2) + 'T00:00:00.000Z';

  const timed = db
    .prepare(
      `SELECT * FROM events
       WHERE deleted_at IS NULL AND all_day = 0 AND start_ts < ? AND end_ts > ?`
    )
    .all(toUtc, fromUtc) as Row[];

  const allDay = db
    .prepare(
      `SELECT * FROM events
       WHERE deleted_at IS NULL AND all_day = 1 AND start_date <= ? AND end_date > ?`
    )
    .all(to, from) as Row[];

  return [...timed, ...allDay].map(normalize);
}

/** Ett enskilt cache-event (för svar efter skrivning). */
export function getEvent(db: Database, id: string): CalendarEvent | null {
  const r = db
    .prepare('SELECT * FROM events WHERE id = ? AND deleted_at IS NULL')
    .get(id) as Row | undefined;
  return r ? normalize(r) : null;
}
