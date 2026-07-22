/**
 * Steg 1 i CalDAV-guiden: discovery. Verifierar uppgifterna och listar
 * kalendrar med VEVENT-stöd. Sparar INGET (spec §9.1).
 */
import { discoverCalendars } from '../_shared/caldav.ts';
import { jsonResponse, handleOptions, requireMember, HttpError } from '../_shared/util.ts';

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    await requireMember(req);
    const { appleId, appPassword } = await req.json();
    if (!appleId || !appPassword) {
      throw new HttpError('validation', 'Ange Apple-ID och app-lösenord.', 400);
    }
    const server = Deno.env.get('CALDAV_SERVER') ?? 'https://caldav.icloud.com';
    try {
      const calendars = await discoverCalendars(server, appleId, appPassword);
      return jsonResponse({
        calendars: calendars.map((c) => ({ href: c.href, name: c.name })),
        targetName: Deno.env.get('CALDAV_CALENDAR_NAME') ?? 'Gemensamt'
      });
    } catch {
      throw new HttpError(
        'caldav_unavailable',
        'Kunde inte hämta kalendrar – kontrollera Apple-ID och app-lösenord.',
        502
      );
    }
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
