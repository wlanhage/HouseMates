/**
 * CalDAV-synk (spec §9.2 översatt till Supabase). Anropas av pg_cron var
 * 5:e minut (service role) eller manuellt av en inloggad medlem.
 * Full omsynk av fönstret; upserts idempotenta på (caldav_uid, recurrence_id);
 * externa raderingar hårdraderas; sync_state uppdateras per användare.
 */
import { fetchCalendarObjects } from '../_shared/caldav.ts';
import {
  serviceClient,
  jsonResponse,
  handleOptions,
  isServiceCall,
  requireHousehold,
  householdUsernames,
  decryptSecret,
  sanitize,
  HttpError
} from '../_shared/util.ts';
import { upsertResource, QUERY_START, QUERY_END } from '../_shared/synccore.ts';

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    // Cron synkar alla hushåll; en användare som drar för att uppdatera bara sitt eget.
    const onlyHousehold = isServiceCall(req) ? null : (await requireHousehold(req)).householdId;

    const svc = serviceClient();
    let query = svc.from('caldav_accounts').select('*');
    if (onlyHousehold) query = query.eq('household_id', onlyHousehold);
    const { data: accounts } = await query;
    if (!accounts?.length) return jsonResponse({ synced: 0, note: 'ingen kalender kopplad' });

    // En synkrunda per unik kalender-href; första fungerande kontot används.
    const byHref = new Map<string, typeof accounts>();
    for (const a of accounts) {
      const list = byHref.get(a.calendar_href) ?? [];
      list.push(a);
      byHref.set(a.calendar_href, list);
    }

    let total = 0;
    for (const [href, group] of byHref) {
      let ok = false;
      for (const acc of group) {
        const usernames = await householdUsernames(svc, acc.household_id);
        let secret = '';
        try {
          secret = await decryptSecret(acc.password_enc);
          const objects = await fetchCalendarObjects(
            href,
            acc.apple_id,
            secret,
            QUERY_START(),
            QUERY_END()
          );
          const seen: string[] = [];
          for (const obj of objects) {
            const abs = obj.href.startsWith('http') ? obj.href : new URL(href).origin + obj.href;
            seen.push(abs);
            await upsertResource(svc, obj.data, abs, obj.etag, usernames, acc.household_id);
            total++;
          }
          // Hårdradera resurser som försvunnit externt (ingen ångra).
          const keep = seen.map((h) => `"${h}"`).join(',');
          let del = svc
            .from('events')
            .delete()
            .eq('household_id', acc.household_id)
            .like('caldav_href', `${href}%`);
          if (seen.length) del = del.not('caldav_href', 'in', `(${keep})`);
          await del;
          ok = true;
          break;
        } catch (err) {
          // failing_since sätts bara om den inte redan är satt (spec §9.2)
          const { data: cur } = await svc
            .from('sync_state')
            .select('failing_since')
            .eq('username', acc.username)
            .maybeSingle();
          await svc.from('sync_state').upsert({
            username: acc.username,
            last_error: sanitize(err, secret),
            failing_since: cur?.failing_since ?? new Date().toISOString()
          });
        }
      }
      if (ok) {
        for (const acc of group) {
          await svc.from('sync_state').upsert({
            username: acc.username,
            last_synced_at: new Date().toISOString(),
            last_error: null,
            failing_since: null
          });
        }
      }
    }
    return jsonResponse({ synced: total });
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
