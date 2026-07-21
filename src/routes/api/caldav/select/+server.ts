import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok, apiError, readJson, catchHttp } from '$lib/server/http';
import { encrypt } from '$lib/server/crypto';
import { makeClient, discoverCalendars } from '$lib/server/caldav/client';
import { runSyncNow } from '$lib/server/jobs';

/** Steg 2: verifiera + spara krypterade credentials + href på användaren (§7.6). */
export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const { appleId, appPassword, href } = await readJson<{
      appleId?: string;
      appPassword?: string;
      href?: string;
    }>(request);
    if (!appleId || !appPassword || !href) {
      return apiError('validation', 'Uppgifter saknas.', 400);
    }

    // Verifiera att uppgifterna fungerar innan vi sparar.
    try {
      const client = await makeClient(appleId, appPassword);
      const calendars = await discoverCalendars(client);
      if (!calendars.some((c) => c.href === href)) {
        return apiError('validation', 'Kalendern hittades inte.', 400);
      }
    } catch {
      return apiError('caldav_unavailable', 'Kunde inte ansluta till iCloud.', 502);
    }

    db.prepare(
      'UPDATE users SET caldav_username = ?, caldav_password_enc = ?, caldav_calendar_href = ? WHERE id = ?'
    ).run(appleId, encrypt(appPassword), href, locals.user!.id);

    void runSyncNow(); // fyll cachen direkt (i bakgrunden)
    return ok({ ok: true });
  } catch (e) {
    return catchHttp(e);
  }
};
