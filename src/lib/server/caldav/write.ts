/**
 * Skrivflöde mot CalDAV (spec §9.4). Create/update/delete/restore med
 * etag-hantering. HTTP 412 (någon hann före) → resynka + caldav_conflict.
 * Eventmutationer köas ALDRIG offline (§7.5) – endpointen kräver nät.
 */
import { randomUUID } from 'node:crypto';
import { db, now } from '../db';
import { decrypt } from '../crypto';
import { HttpError } from '../http';
import { logActivity } from '../activity';
import { getEvent } from '../events';
import { makeClient, type CalClient } from './client';
import { buildVCalendar, updateRawIcs, parseResource, type EventFields } from './ics';
import type { CalendarEvent } from '$lib/types';

const DAY = 86_400_000;

interface EventRowDb {
  id: string;
  caldav_uid: string;
  recurrence_id: string;
  caldav_href: string | null;
  etag: string | null;
  raw_ics: string | null;
  created_by: string | null;
  deleted_at: string | null;
}

async function clientForUser(userId: string): Promise<{ client: CalClient; calendarHref: string }> {
  const u = db
    .prepare(
      'SELECT caldav_username, caldav_password_enc, caldav_calendar_href FROM users WHERE id = ?'
    )
    .get(userId) as
    | { caldav_username: string; caldav_password_enc: Buffer; caldav_calendar_href: string | null }
    | undefined;
  if (!u?.caldav_calendar_href || !u.caldav_password_enc) {
    throw new HttpError('caldav_unavailable', 'Ingen kalender kopplad.', 502);
  }
  const client = await makeClient(u.caldav_username, decrypt(u.caldav_password_enc));
  return { client, calendarHref: u.caldav_calendar_href };
}

const joinUrl = (base: string, name: string) => (base.endsWith('/') ? base + name : base + '/' + name);

/** Läs tillbaka etag + data efter en PUT (spec §9.4). */
async function readBack(
  client: CalClient,
  calendarHref: string,
  objectUrl: string,
  fallbackIcs: string
): Promise<{ data: string; etag: string | null }> {
  try {
    const objs = await client.fetchCalendarObjects({
      calendar: { url: calendarHref } as never,
      objectUrls: [objectUrl]
    });
    if (objs[0]?.data) return { data: objs[0].data, etag: objs[0].etag ?? null };
  } catch {
    /* faller tillbaka på det vi skickade */
  }
  return { data: fallbackIcs, etag: null };
}

/** Upserta en resurs rader i cachen; returnera master-radens id. */
function upsertResourceRows(
  data: string,
  href: string,
  etag: string | null,
  createdBy: string | null
): string {
  const winStart = new Date(Date.now() - 30 * DAY);
  const winEnd = new Date(Date.now() + 180 * DAY);
  const rows = parseResource(data, winStart, winEnd);
  const ts = now();
  let masterId = '';
  const run = db.transaction(() => {
    for (const r of rows) {
      const existing = db
        .prepare('SELECT id FROM events WHERE caldav_uid = ? AND recurrence_id = ?')
        .get(r.caldav_uid, r.recurrence_id) as { id: string } | undefined;
      const id = existing?.id ?? randomUUID();
      if (r.recurrence_id === '' || !masterId) masterId = id;
      db.prepare(
        `INSERT INTO events (id, caldav_uid, recurrence_id, caldav_href, etag, title, location, notes,
           all_day, start_ts, end_ts, start_date, end_date, created_by, raw_ics, synced_at, updated_at, deleted_at, deleted_by)
         VALUES (@id,@caldav_uid,@recurrence_id,@href,@etag,@title,@location,@notes,@all_day,@start_ts,@end_ts,@start_date,@end_date,@created_by,@raw_ics,@ts,@ts,NULL,NULL)
         ON CONFLICT(caldav_uid, recurrence_id) DO UPDATE SET
           caldav_href=excluded.caldav_href, etag=excluded.etag, title=excluded.title,
           location=excluded.location, notes=excluded.notes, all_day=excluded.all_day,
           start_ts=excluded.start_ts, end_ts=excluded.end_ts, start_date=excluded.start_date,
           end_date=excluded.end_date, raw_ics=excluded.raw_ics, synced_at=excluded.synced_at,
           updated_at=excluded.synced_at, deleted_at=NULL, deleted_by=NULL`
      ).run({
        id,
        caldav_uid: r.caldav_uid,
        recurrence_id: r.recurrence_id,
        href,
        etag,
        title: r.title,
        location: r.location,
        notes: r.notes,
        all_day: r.all_day,
        start_ts: r.start_ts,
        end_ts: r.end_ts,
        start_date: r.start_date,
        end_date: r.end_date,
        created_by: createdBy,
        ts
      });
    }
  });
  run();
  return masterId;
}

const rowById = (id: string): EventRowDb | undefined =>
  db
    .prepare('SELECT id, caldav_uid, recurrence_id, caldav_href, etag, raw_ics, created_by, deleted_at FROM events WHERE id = ?')
    .get(id) as EventRowDb | undefined;

export async function createEvent(userId: string, fields: Omit<EventFields, 'uid'>): Promise<CalendarEvent> {
  const uid = `app-${userId}-${randomUUID()}`;
  const ics = buildVCalendar({ ...fields, uid });
  const { client, calendarHref } = await clientForUser(userId);
  const filename = `${uid}.ics`;
  const objectUrl = joinUrl(calendarHref, filename);

  try {
    const res = await client.createCalendarObject({
      calendar: { url: calendarHref } as never,
      filename,
      iCalString: ics
    });
    if (!res.ok) throw new Error(`PUT ${res.status}`);
  } catch {
    throw new HttpError('caldav_unavailable', 'Kunde inte spara i iCloud.', 502);
  }

  const { data, etag } = await readBack(client, calendarHref, objectUrl, ics);
  const id = upsertResourceRows(data, objectUrl, etag, userId);
  logActivity(db, {
    type: 'event.created',
    actor: userId,
    entityType: 'event',
    entityId: id,
    payload: { title: fields.title, start: fields.start }
  });
  return getEvent(db, id)!;
}

export async function updateEvent(
  userId: string,
  id: string,
  changes: Partial<Omit<EventFields, 'uid'>>
): Promise<CalendarEvent> {
  const row = rowById(id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Händelsen finns inte.', 404);
  if (row.recurrence_id !== '') {
    throw new HttpError('validation', 'Kan inte redigera en enskild förekomst i en serie.', 422);
  }
  if (!row.raw_ics || !row.caldav_href) {
    throw new HttpError('caldav_unavailable', 'Saknar original – synka först.', 502);
  }

  const newIcs = updateRawIcs(row.raw_ics, changes);
  const { client, calendarHref } = await clientForUser(userId);

  let res: Response;
  try {
    res = await client.updateCalendarObject({
      calendarObject: { url: row.caldav_href, data: newIcs, etag: row.etag ?? undefined }
    });
  } catch {
    throw new HttpError('caldav_unavailable', 'Kunde inte nå iCloud.', 502);
  }

  if (res.status === 412) {
    // Någon hann före → resynka just denna resurs och svara konflikt.
    const fresh = await readBack(client, calendarHref, row.caldav_href, row.raw_ics);
    const freshId = upsertResourceRows(fresh.data, row.caldav_href, fresh.etag, row.created_by);
    throw new HttpError('caldav_conflict', 'Händelsen ändrades av någon annan.', 409, {
      current: getEvent(db, freshId)
    });
  }
  if (!res.ok) throw new HttpError('caldav_unavailable', 'Kunde inte spara i iCloud.', 502);

  const { data, etag } = await readBack(client, calendarHref, row.caldav_href, newIcs);
  const newId = upsertResourceRows(data, row.caldav_href, etag, row.created_by);
  logActivity(db, {
    type: 'event.updated',
    actor: userId,
    entityType: 'event',
    entityId: newId,
    payload: { title: changes.title ?? '' }
  });
  return getEvent(db, newId)!;
}

export async function deleteEvent(userId: string, id: string): Promise<{ title: string }> {
  const row = rowById(id);
  if (!row || row.deleted_at) throw new HttpError('not_found', 'Händelsen finns inte.', 404);
  if (!row.caldav_href) throw new HttpError('caldav_unavailable', 'Saknar resurs.', 502);

  const { client, calendarHref } = await clientForUser(userId);
  let res: Response;
  try {
    res = await client.deleteCalendarObject({
      calendarObject: { url: row.caldav_href, etag: row.etag ?? undefined }
    });
  } catch {
    throw new HttpError('caldav_unavailable', 'Kunde inte nå iCloud.', 502);
  }
  if (res.status === 412) {
    const fresh = await readBack(client, calendarHref, row.caldav_href, row.raw_ics ?? '');
    const freshId = upsertResourceRows(fresh.data, row.caldav_href, fresh.etag, row.created_by);
    throw new HttpError('caldav_conflict', 'Händelsen ändrades av någon annan.', 409, {
      current: getEvent(db, freshId)
    });
  }
  if (!res.ok) throw new HttpError('caldav_unavailable', 'Kunde inte radera i iCloud.', 502);

  // Soft delete alla rader för resursen (ångra-fönster).
  const titleRow = db.prepare('SELECT title FROM events WHERE id = ?').get(id) as { title: string };
  db.prepare(
    'UPDATE events SET deleted_at = ?, deleted_by = ? WHERE caldav_href = ?'
  ).run(now(), userId, row.caldav_href);
  logActivity(db, {
    type: 'event.deleted',
    actor: userId,
    entityType: 'event',
    entityId: id,
    payload: { title: titleRow?.title ?? '' }
  });
  return { title: titleRow?.title ?? '' };
}

export async function restoreEvent(userId: string, id: string): Promise<CalendarEvent> {
  const row = rowById(id);
  if (!row) throw new HttpError('not_found', 'Händelsen finns inte.', 404);
  if (!row.raw_ics || !row.caldav_href) {
    throw new HttpError('caldav_unavailable', 'Saknar original.', 502);
  }
  const { client, calendarHref } = await clientForUser(userId);
  const filename = row.caldav_href.split('/').pop() || `${row.caldav_uid}.ics`;
  try {
    const res = await client.createCalendarObject({
      calendar: { url: calendarHref } as never,
      filename,
      iCalString: row.raw_ics
    });
    if (!res.ok) throw new Error(`PUT ${res.status}`);
  } catch {
    throw new HttpError('caldav_unavailable', 'Kunde inte återställa i iCloud.', 502);
  }
  const { data, etag } = await readBack(client, calendarHref, row.caldav_href, row.raw_ics);
  const newId = upsertResourceRows(data, row.caldav_href, etag, row.created_by);
  logActivity(db, {
    type: 'event.restored',
    actor: userId,
    entityType: 'event',
    entityId: newId,
    payload: { title: '' }
  });
  return getEvent(db, newId)!;
}
