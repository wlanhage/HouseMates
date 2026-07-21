import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { ok, apiError, readJson } from '$lib/server/http';
import { makeClient, discoverCalendars } from '$lib/server/caldav/client';

/** Steg 1 i CalDAV-wizarden: discovery. Sparar INGET (spec §7.6/§9.1). */
export const POST: RequestHandler = async ({ request }) => {
  const { appleId, appPassword } = await readJson<{ appleId?: string; appPassword?: string }>(request);
  if (!appleId || !appPassword) {
    return apiError('validation', 'Ange Apple-ID och app-lösenord.', 400);
  }
  try {
    const client = await makeClient(appleId, appPassword);
    const calendars = await discoverCalendars(client);
    return ok({
      calendars: calendars.map((c) => ({ href: c.href, name: c.displayName })),
      targetName: env.CALDAV_CALENDAR_NAME ?? ''
    });
  } catch {
    return apiError(
      'caldav_unavailable',
      'Kunde inte hämta kalendrar – kontrollera Apple-ID och app-lösenord.',
      502
    );
  }
};
