/**
 * Skrivflöde mot CalDAV (spec §9.4): create/update/delete/restore med
 * etag-hantering. HTTP 412 → resynka resursen + 409 caldav_conflict med
 * färsk kopia. Aktivitet loggas (triggern köar notisen till partnern).
 */
import {
  putCalendarObject,
  deleteCalendarObject,
  getCalendarObject
} from '../_shared/caldav.ts';
import { buildVCalendar, updateRawIcs } from '../_shared/ics.ts';
import {
  serviceClient,
  jsonResponse,
  handleOptions,
  requireMember,
  decryptSecret,
  HttpError
} from '../_shared/util.ts';
import { upsertResource, getEventRow } from '../_shared/synccore.ts';

interface Creds {
  appleId: string;
  password: string;
  calendarHref: string;
}

async function credsFor(svc: ReturnType<typeof serviceClient>, username: string): Promise<Creds> {
  const { data } = await svc.from('caldav_accounts').select('*').eq('username', username).maybeSingle();
  if (!data) throw new HttpError('caldav_unavailable', 'Ingen kalender kopplad.', 502);
  return {
    appleId: data.apple_id,
    password: await decryptSecret(data.password_enc),
    calendarHref: data.calendar_href
  };
}

async function usernames(svc: ReturnType<typeof serviceClient>): Promise<string[]> {
  const { data } = await svc.from('profiles').select('username');
  return (data ?? []).map((p: { username: string }) => p.username);
}

async function logActivity(
  svc: ReturnType<typeof serviceClient>,
  type: string,
  actor: string,
  entityId: string,
  payload: Record<string, unknown>
): Promise<void> {
  await svc.from('activity_log').insert({
    type,
    actor,
    entity_type: 'event',
    entity_id: entityId,
    payload
  });
}

/** Läs tillbaka resursen efter skrivning och upserta cachen. */
async function readBackAndUpsert(
  svc: ReturnType<typeof serviceClient>,
  creds: Creds,
  objectUrl: string,
  fallbackIcs: string,
  users: string[]
): Promise<string | null> {
  const fresh = await getCalendarObject(objectUrl, creds.appleId, creds.password);
  return upsertResource(
    svc,
    fresh?.data ?? fallbackIcs,
    objectUrl,
    fresh?.etag ?? null,
    users
  );
}

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    const me = await requireMember(req);
    const body = await req.json();
    const action = body.action as string;
    const svc = serviceClient();
    const users = await usernames(svc);
    const creds = await credsFor(svc, me);
    const joinUrl = (base: string, name: string) =>
      base.endsWith('/') ? base + name : base + '/' + name;

    if (action === 'create') {
      const { title, allDay, start, end, location, notes } = body;
      if (!title?.trim() || !start || !end) throw new HttpError('validation', 'Titel och tider krävs.', 400);
      if ((allDay && !(end > start)) || (!allDay && Date.parse(end) <= Date.parse(start))) {
        throw new HttpError('validation', 'Slut måste vara efter start.', 400);
      }
      const uid = `app-${me}-${crypto.randomUUID()}`;
      const ics = buildVCalendar({ uid, title: title.trim(), allDay, start, end, location, notes });
      const objectUrl = joinUrl(creds.calendarHref, `${uid}.ics`);
      const res = await putCalendarObject(objectUrl, creds.appleId, creds.password, ics, null);
      if (res.status >= 300) throw new HttpError('caldav_unavailable', 'Kunde inte spara i kalendern.', 502);
      const id = await readBackAndUpsert(svc, creds, objectUrl, ics, users);
      if (!id) throw new HttpError('caldav_unavailable', 'Kunde inte läsa tillbaka.', 502);
      await logActivity(svc, 'event.created', me, id, { title: title.trim(), start });
      return jsonResponse({ event: await getEventRow(svc, id) });
    }

    // Övriga actions kräver ett befintligt cache-event.
    const { data: row } = await svc.from('events').select('*').eq('id', body.id).maybeSingle();
    if (!row) throw new HttpError('not_found', 'Händelsen finns inte.', 404);

    if (action === 'update') {
      if (row.recurrence_id !== '') {
        throw new HttpError('validation', 'Enskilda förekomster kan inte redigeras i v1.', 422);
      }
      if (!row.raw_ics || !row.caldav_href) {
        throw new HttpError('caldav_unavailable', 'Saknar original – synka först.', 502);
      }
      const newIcs = updateRawIcs(row.raw_ics, {
        title: body.title,
        allDay: body.allDay,
        start: body.start,
        end: body.end,
        location: body.location,
        notes: body.notes
      });
      const res = await putCalendarObject(row.caldav_href, creds.appleId, creds.password, newIcs, row.etag);
      if (res.status === 412) {
        const freshId = await readBackAndUpsert(svc, creds, row.caldav_href, row.raw_ics, users);
        throw new HttpError('caldav_conflict', 'Händelsen ändrades av någon annan.', 409, {
          current: freshId ? await getEventRow(svc, freshId) : null
        });
      }
      if (res.status >= 300) throw new HttpError('caldav_unavailable', 'Kunde inte spara.', 502);
      const id = await readBackAndUpsert(svc, creds, row.caldav_href, newIcs, users);
      await logActivity(svc, 'event.updated', me, id ?? row.id, { title: body.title ?? row.title });
      return jsonResponse({ event: id ? await getEventRow(svc, id) : null });
    }

    if (action === 'delete') {
      if (!row.caldav_href) throw new HttpError('caldav_unavailable', 'Saknar resurs.', 502);
      const status = await deleteCalendarObject(row.caldav_href, creds.appleId, creds.password, row.etag);
      if (status === 412) {
        const freshId = await readBackAndUpsert(svc, creds, row.caldav_href, row.raw_ics ?? '', users);
        throw new HttpError('caldav_conflict', 'Händelsen ändrades av någon annan.', 409, {
          current: freshId ? await getEventRow(svc, freshId) : null
        });
      }
      if (status >= 300 && status !== 404) {
        throw new HttpError('caldav_unavailable', 'Kunde inte radera.', 502);
      }
      const ts = new Date().toISOString();
      await svc
        .from('events')
        .update({ deleted_at: ts, deleted_by: me })
        .eq('caldav_href', row.caldav_href);
      await logActivity(svc, 'event.deleted', me, row.id, { title: row.title });
      return jsonResponse({ ok: true });
    }

    if (action === 'restore') {
      if (!row.raw_ics || !row.caldav_href) throw new HttpError('caldav_unavailable', 'Saknar original.', 502);
      const res = await putCalendarObject(row.caldav_href, creds.appleId, creds.password, row.raw_ics, null);
      if (res.status >= 300 && res.status !== 412) {
        throw new HttpError('caldav_unavailable', 'Kunde inte återställa.', 502);
      }
      const id = await readBackAndUpsert(svc, creds, row.caldav_href, row.raw_ics, users);
      await logActivity(svc, 'event.restored', me, id ?? row.id, { title: row.title });
      return jsonResponse({ event: id ? await getEventRow(svc, id) : null });
    }

    throw new HttpError('validation', 'Okänd action.', 400);
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
