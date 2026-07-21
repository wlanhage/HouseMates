/**
 * tsdav-uppkoppling + discovery (spec §9.1). Basic auth mot CALDAV_SERVER
 * med Apple-ID + app-specifikt lösenord.
 */
import { createDAVClient } from 'tsdav';
import { env } from '$env/dynamic/private';

/** Klienttypen som createDAVClient faktiskt returnerar (metoderna). */
export type CalClient = Awaited<ReturnType<typeof createDAVClient>>;

export function makeClient(appleId: string, appPassword: string): Promise<CalClient> {
  return createDAVClient({
    serverUrl: env.CALDAV_SERVER ?? 'https://caldav.icloud.com',
    credentials: { username: appleId, password: appPassword },
    authMethod: 'Basic',
    defaultAccountType: 'caldav'
  });
}

export interface DiscoveredCalendar {
  href: string;
  displayName: string;
}

function nameOf(displayName: unknown, fallback: string): string {
  if (typeof displayName === 'string') return displayName;
  if (displayName && typeof displayName === 'object' && '_cdata' in displayName) {
    return String((displayName as { _cdata: unknown })._cdata);
  }
  return fallback;
}

/** Kalendrar med VEVENT-stöd (spec §9.1). */
export async function discoverCalendars(client: CalClient): Promise<DiscoveredCalendar[]> {
  const calendars = await client.fetchCalendars();
  return calendars
    .filter((c) => {
      const comps = c.components as string[] | undefined;
      return !comps || comps.includes('VEVENT');
    })
    .map((c) => ({ href: c.url, displayName: nameOf(c.displayName, c.url) }));
}
