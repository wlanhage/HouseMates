/**
 * Steg 2 i CalDAV-guiden: verifiera vald kalender + spara krypterade
 * uppgifter på medlemmen (spec §7.6/§9.1). Lösenordet AES-krypteras i vila.
 * Ett kopplat konto per hushåll: partnern använder samma koppling.
 */
import { discoverCalendars } from '../_shared/caldav.ts';
import {
  serviceClient,
  jsonResponse,
  handleOptions,
  requireMember,
  encryptSecret,
  HttpError
} from '../_shared/util.ts';

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    const username = await requireMember(req);
    const { appleId, appPassword, href } = await req.json();
    if (!appleId || !appPassword || !href) {
      throw new HttpError('validation', 'Uppgifter saknas.', 400);
    }

    const server = Deno.env.get('CALDAV_SERVER') ?? 'https://caldav.icloud.com';
    let calendars;
    try {
      calendars = await discoverCalendars(server, appleId, appPassword);
    } catch {
      throw new HttpError('caldav_unavailable', 'Kunde inte ansluta till kalendertjänsten.', 502);
    }
    if (!calendars.some((c) => c.href === href)) {
      throw new HttpError('validation', 'Kalendern hittades inte.', 400);
    }

    const svc = serviceClient();
    const { data: other } = await svc
      .from('caldav_accounts')
      .select('username, profiles(name)')
      .neq('username', username)
      .maybeSingle();
    if (other) {
      const name = ((other as { profiles?: { name?: string } }).profiles?.name ?? other.username).replace(/\s*\(test\)/, '');
      throw new HttpError(
        'already_linked',
        `Kalendern är redan kopplad via ${name}. Koppla från där först om ni vill byta konto.`,
        409
      );
    }
    const { error } = await svc.from('caldav_accounts').upsert({
      username,
      apple_id: appleId,
      password_enc: await encryptSecret(appPassword),
      calendar_href: href,
      updated_at: new Date().toISOString()
    });
    if (error) throw error;

    await svc.from('sync_state').upsert({ username });
    return jsonResponse({ ok: true });
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
