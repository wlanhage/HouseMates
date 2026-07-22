/**
 * Rå CalDAV-klient för Deno/Edge – ingen tsdav, bara fetch + XML.
 * Fungerar mot iCloud och Radicale (namespace-agnostisk parsning).
 */
// @ts-expect-error npm-import i Deno saknar typer här
import { XMLParser } from 'npm:fast-xml-parser@4.5.0';

export interface CalResource {
  href: string;
  etag: string | null;
  data: string;
}

const parser = new XMLParser({
  removeNSPrefix: true,
  ignoreAttributes: false,
  isArray: (name: string) => name === 'response' || name === 'propstat'
});

function basicAuth(user: string, pass: string): string {
  return 'Basic ' + btoa(`${user}:${pass}`);
}

/** Alla VEVENT-resurser i kalendern inom tidsfönstret. */
export async function fetchCalendarObjects(
  calendarUrl: string,
  username: string,
  password: string,
  start: Date,
  end: Date
): Promise<CalResource[]> {
  const fmt = (d: Date) =>
    d.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  const body = `<?xml version="1.0" encoding="utf-8"?>
<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop><d:getetag/><c:calendar-data/></d:prop>
  <c:filter>
    <c:comp-filter name="VCALENDAR">
      <c:comp-filter name="VEVENT">
        <c:time-range start="${fmt(start)}" end="${fmt(end)}"/>
      </c:comp-filter>
    </c:comp-filter>
  </c:filter>
</c:calendar-query>`;

  const res = await fetch(calendarUrl, {
    method: 'REPORT',
    headers: {
      Authorization: basicAuth(username, password),
      Depth: '1',
      'Content-Type': 'application/xml; charset=utf-8'
    },
    body
  });
  if (!res.ok) throw new Error(`CalDAV REPORT ${res.status}`);

  const doc = parser.parse(await res.text());
  const responses = doc?.multistatus?.response ?? [];
  const out: CalResource[] = [];
  for (const r of responses) {
    const href = typeof r.href === 'object' ? r.href['#text'] : r.href;
    for (const ps of r.propstat ?? []) {
      const status = String(ps.status ?? '');
      if (!status.includes('200')) continue;
      const prop = ps.prop ?? {};
      const data = prop['calendar-data'];
      const dataStr = typeof data === 'object' ? data['#text'] : data;
      if (!dataStr) continue;
      const etagRaw = prop.getetag;
      const etag = etagRaw == null ? null : String(typeof etagRaw === 'object' ? etagRaw['#text'] : etagRaw);
      out.push({ href: String(href), etag, data: String(dataStr) });
    }
  }
  return out;
}

/** PUT en ICS-resurs. ifMatch=etag för uppdatering, '*'-none för create. */
export async function putCalendarObject(
  objectUrl: string,
  username: string,
  password: string,
  ics: string,
  etag: string | null
): Promise<{ status: number; etag: string | null }> {
  const headers: Record<string, string> = {
    Authorization: basicAuth(username, password),
    'Content-Type': 'text/calendar; charset=utf-8'
  };
  if (etag) headers['If-Match'] = etag;
  else headers['If-None-Match'] = '*';
  const res = await fetch(objectUrl, { method: 'PUT', headers, body: ics });
  return { status: res.status, etag: res.headers.get('etag') };
}

/** DELETE en resurs med If-Match. */
export async function deleteCalendarObject(
  objectUrl: string,
  username: string,
  password: string,
  etag: string | null
): Promise<number> {
  const headers: Record<string, string> = { Authorization: basicAuth(username, password) };
  if (etag) headers['If-Match'] = etag;
  const res = await fetch(objectUrl, { method: 'DELETE', headers });
  return res.status;
}
