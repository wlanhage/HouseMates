/**
 * CalDAV-synkmotor (spec §9.2). Full omsynk per kalender-href i fönstret
 * [idag−60d, idag+365d]; RRULE expanderas i [idag−30d, idag+180d]. Upserts är
 * idempotenta på (caldav_uid, recurrence_id). Externa raderingar hårdraderas.
 */
import { randomUUID } from 'node:crypto';
import { db, now } from '../db';
import { decrypt } from '../crypto';
import { makeClient } from './client';
import { parseResource, type EventRow } from './ics';
import { broadcast } from '../sse';

const DAY = 86_400_000;

interface CalUser {
  id: string;
  caldav_username: string;
  caldav_password_enc: Buffer;
  caldav_calendar_href: string;
}

function createdByFromUid(uid: string, userIds: string[]): string | null {
  for (const id of userIds) if (uid.startsWith(`app-${id}-`)) return id;
  return null;
}

/** Ta bort ev. lösenord/token ur felmeddelanden innan de sparas (spec §14). */
function sanitize(err: unknown, secret: string): string {
  let msg = err instanceof Error ? err.message : String(err);
  if (secret) msg = msg.split(secret).join('***');
  return msg.slice(0, 300);
}

const upsertStmt = db.prepare(`
  INSERT INTO events (id, caldav_uid, recurrence_id, caldav_href, etag, title, location, notes,
                      all_day, start_ts, end_ts, start_date, end_date, created_by, raw_ics, synced_at, updated_at)
  VALUES (@id, @caldav_uid, @recurrence_id, @caldav_href, @etag, @title, @location, @notes,
          @all_day, @start_ts, @end_ts, @start_date, @end_date, @created_by, @raw_ics, @synced_at, @synced_at)
  ON CONFLICT(caldav_uid, recurrence_id) DO UPDATE SET
    caldav_href = excluded.caldav_href, etag = excluded.etag, title = excluded.title,
    location = excluded.location, notes = excluded.notes, all_day = excluded.all_day,
    start_ts = excluded.start_ts, end_ts = excluded.end_ts, start_date = excluded.start_date,
    end_date = excluded.end_date, created_by = excluded.created_by, raw_ics = excluded.raw_ics,
    synced_at = excluded.synced_at, updated_at = excluded.synced_at, deleted_at = NULL, deleted_by = NULL
`);

function upsertResource(
  data: string,
  href: string,
  etag: string | undefined,
  winStart: Date,
  winEnd: Date,
  userIds: string[]
): void {
  let rows: EventRow[];
  try {
    rows = parseResource(data, winStart, winEnd);
  } catch {
    return; // trasig ICS – hoppa över resursen
  }
  const ts = now();
  const recIds: string[] = [];
  for (const r of rows) {
    recIds.push(r.recurrence_id);
    const existing = db
      .prepare('SELECT id FROM events WHERE caldav_uid = ? AND recurrence_id = ?')
      .get(r.caldav_uid, r.recurrence_id) as { id: string } | undefined;
    upsertStmt.run({
      id: existing?.id ?? randomUUID(),
      caldav_uid: r.caldav_uid,
      recurrence_id: r.recurrence_id,
      caldav_href: href,
      etag: etag ?? null,
      title: r.title,
      location: r.location,
      notes: r.notes,
      all_day: r.all_day,
      start_ts: r.start_ts,
      end_ts: r.end_ts,
      start_date: r.start_date,
      end_date: r.end_date,
      created_by: rows.length ? createdByFromUid(r.caldav_uid, userIds) : null,
      raw_ics: data,
      synced_at: ts
    });
  }
  // Städa bort förekomster som inte längre finns i resursen.
  if (rows.length) {
    const uid = rows[0].caldav_uid;
    const placeholders = recIds.map(() => '?').join(',');
    db.prepare(
      `DELETE FROM events WHERE caldav_uid = ? AND recurrence_id NOT IN (${placeholders})`
    ).run(uid, ...recIds);
  }
}

async function pullCalendar(href: string, userIds: string[], client: Awaited<ReturnType<typeof makeClient>>): Promise<boolean> {
  const start = new Date(Date.now() - 60 * DAY);
  const end = new Date(Date.now() + 365 * DAY);
  const winStart = new Date(Date.now() - 30 * DAY);
  const winEnd = new Date(Date.now() + 180 * DAY);

  const objects = await client.fetchCalendarObjects({
    calendar: { url: href } as never,
    timeRange: { start: start.toISOString(), end: end.toISOString() }
  });

  const seen = new Set<string>();
  const run = db.transaction(() => {
    for (const obj of objects) {
      if (!obj.data) continue;
      seen.add(obj.url);
      upsertResource(obj.data, obj.url, obj.etag, winStart, winEnd, userIds);
    }
    // Hårdradera resurser som försvunnit externt (ingen ångra på externa raderingar).
    const cached = db
      .prepare('SELECT DISTINCT caldav_href FROM events WHERE caldav_href LIKE ?')
      .all(href + '%') as { caldav_href: string }[];
    for (const { caldav_href } of cached) {
      if (caldav_href && !seen.has(caldav_href)) {
        db.prepare('DELETE FROM events WHERE caldav_href = ?').run(caldav_href);
      }
    }
  });
  run();
  return true;
}

function markOk(userId: string): void {
  db.prepare(
    `INSERT INTO sync_state (user_id, last_synced_at, last_error, failing_since)
     VALUES (?, ?, NULL, NULL)
     ON CONFLICT(user_id) DO UPDATE SET last_synced_at = excluded.last_synced_at,
       last_error = NULL, failing_since = NULL`
  ).run(userId, now());
}

function markFail(userId: string, error: string): void {
  db.prepare(
    `INSERT INTO sync_state (user_id, last_error, failing_since)
     VALUES (?, ?, ?)
     ON CONFLICT(user_id) DO UPDATE SET last_error = excluded.last_error,
       failing_since = COALESCE(sync_state.failing_since, excluded.failing_since)`
  ).run(userId, error, now());
}

/** En synkrunda över alla konfigurerade kalendrar. */
export async function syncAll(): Promise<void> {
  const users = db
    .prepare(
      `SELECT id, caldav_username, caldav_password_enc, caldav_calendar_href
       FROM users WHERE caldav_calendar_href IS NOT NULL AND caldav_password_enc IS NOT NULL`
    )
    .all() as CalUser[];

  const byHref = new Map<string, CalUser[]>();
  for (const u of users) {
    const list = byHref.get(u.caldav_calendar_href) ?? [];
    list.push(u);
    byHref.set(u.caldav_calendar_href, list);
  }

  for (const [href, group] of byHref) {
    const userIds = group.map((u) => u.id);
    let ok = false;
    for (const u of group) {
      let secret = '';
      try {
        secret = decrypt(u.caldav_password_enc);
        const client = await makeClient(u.caldav_username, secret);
        await pullCalendar(href, userIds, client);
        ok = true;
        break;
      } catch (err) {
        markFail(u.id, sanitize(err, secret));
      }
    }
    if (ok) {
      for (const u of group) markOk(u.id);
      broadcast('events');
    }
  }
}
