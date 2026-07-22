/**
 * CalDAV-synk som Supabase Edge Function.
 * PoC-läge: anropas med ?poc=1 → hämtar + parsar och returnerar rader som
 * JSON utan att röra databasen (används för verifiering mot testserver).
 * Skarpt läge (DB-upsert) kopplas på efter schema-migreringen.
 */
import { fetchCalendarObjects } from './caldav.ts';
import { parseResource, type EventRow } from './ics.ts';

const DAY = 86_400_000;

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const poc = url.searchParams.get('poc') === '1';

    // PoC: parametrar via query/env; skarpt läge läser krypterade creds ur DB.
    const calendarUrl =
      url.searchParams.get('cal') ?? Deno.env.get('CALDAV_TEST_URL') ?? '';
    const username = url.searchParams.get('user') ?? 'test';
    const password = url.searchParams.get('pass') ?? 'x';
    if (!calendarUrl) {
      return Response.json({ error: 'ingen kalender-url' }, { status: 400 });
    }

    const queryStart = new Date(Date.now() - 60 * DAY);
    const queryEnd = new Date(Date.now() + 365 * DAY);
    const winStart = new Date(Date.now() - 30 * DAY);
    const winEnd = new Date(Date.now() + 180 * DAY);

    const resources = await fetchCalendarObjects(
      calendarUrl,
      username,
      password,
      queryStart,
      queryEnd
    );

    const rows: (EventRow & { href: string; etag: string | null })[] = [];
    for (const r of resources) {
      try {
        for (const row of parseResource(r.data, winStart, winEnd)) {
          rows.push({ ...row, href: r.href, etag: r.etag });
        }
      } catch (_e) {
        /* trasig ICS – hoppa över resursen */
      }
    }

    if (poc) {
      return Response.json({ resources: resources.length, rows });
    }
    // TODO (efter migrering): upsert till Postgres + sync_state.
    return Response.json({ resources: resources.length, parsed: rows.length });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});
