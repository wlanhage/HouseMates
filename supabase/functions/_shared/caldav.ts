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

/** GET en enskild resurs (för etag + data efter skrivning). */
export async function getCalendarObject(
  objectUrl: string,
  username: string,
  password: string
): Promise<{ data: string; etag: string | null } | null> {
  const res = await fetch(objectUrl, {
    headers: { Authorization: basicAuth(username, password) }
  });
  if (!res.ok) return null;
  return { data: await res.text(), etag: res.headers.get('etag') };
}

// ── Discovery (spec §9.1): principal → home-set → kalendrar ──

async function propfind(
  url: string,
  username: string,
  password: string,
  depth: '0' | '1',
  body: string
): Promise<any> {
  const res = await fetch(url, {
    method: 'PROPFIND',
    headers: {
      Authorization: basicAuth(username, password),
      Depth: depth,
      'Content-Type': 'application/xml; charset=utf-8'
    },
    body
  });
  if (res.status === 401) throw new Error('unauthorized');
  if (!res.ok && res.status !== 207) throw new Error(`PROPFIND ${res.status}`);
  return parser.parse(await res.text());
}

const text = (v: unknown): string | null => {
  if (v == null) return null;
  if (typeof v === 'object') return text((v as Record<string, unknown>)['#text'] ?? (v as Record<string, unknown>).href);
  return String(v);
};

function firstProp(doc: any, prop: string): string | null {
  for (const r of doc?.multistatus?.response ?? []) {
    for (const ps of r.propstat ?? []) {
      const v = ps.prop?.[prop];
      if (v != null) {
        const inner = typeof v === 'object' && 'href' in v ? v.href : v;
        const s = text(inner);
        if (s) return s;
      }
    }
  }
  return null;
}

export interface DiscoveredCalendar {
  href: string;
  name: string;
}

/** Hitta alla VEVENT-kalendrar för kontot. */
export async function discoverCalendars(
  serverUrl: string,
  username: string,
  password: string
): Promise<DiscoveredCalendar[]> {
  const origin = new URL(serverUrl).origin;
  const abs = (href: string) => (href.startsWith('http') ? href : origin + href);

  const p1 = await propfind(
    serverUrl,
    username,
    password,
    '0',
    `<?xml version="1.0"?><d:propfind xmlns:d="DAV:"><d:prop><d:current-user-principal/></d:prop></d:propfind>`
  );
  const principal = firstProp(p1, 'current-user-principal');
  if (!principal) throw new Error('ingen principal');

  const p2 = await propfind(
    abs(principal),
    username,
    password,
    '0',
    `<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>`
  );
  const home = firstProp(p2, 'calendar-home-set');
  if (!home) throw new Error('inget calendar-home-set');

  const p3 = await propfind(
    abs(home),
    username,
    password,
    '1',
    `<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:displayname/><d:resourcetype/><c:supported-calendar-component-set/></d:prop></d:propfind>`
  );

  const out: DiscoveredCalendar[] = [];
  for (const r of p3?.multistatus?.response ?? []) {
    const href = text(r.href);
    if (!href) continue;
    for (const ps of r.propstat ?? []) {
      const prop = ps.prop ?? {};
      const isCalendar = prop.resourcetype && 'calendar' in (prop.resourcetype as object);
      if (!isCalendar) continue;
      // komponentstöd: acceptera om VEVENT listas eller om info saknas
      const compSet = prop['supported-calendar-component-set'];
      let hasVevent = true;
      if (compSet && typeof compSet === 'object') {
        const comps = (compSet as Record<string, unknown>).comp;
        const arr = Array.isArray(comps) ? comps : comps ? [comps] : [];
        if (arr.length) {
          hasVevent = arr.some((c) => (c as Record<string, unknown>)['@_name'] === 'VEVENT');
        }
      }
      if (!hasVevent) continue;
      out.push({ href: abs(href), name: text(prop.displayname) ?? href });
    }
  }
  return out;
}
