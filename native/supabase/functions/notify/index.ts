/**
 * Notis-worker: körs varje minut via pg_cron (../../cron.sql). Plockar förfallna
 * rader ur notification_queue per mottagare, bygger EN digest och skickar via APNs.
 * Under mottagarens tysta timmar skjuts raderna upp till när de tar slut.
 * Utan APNs-nyckel körs den torrt och svarar med det som skulle ha skickats.
 */
// @ts-expect-error npm-import i Deno
import { createClient } from 'npm:@supabase/supabase-js@2';
import { buildDigest } from '../_shared/digest.ts';
import { sendApns, type ApnsConfig } from '../_shared/apns.ts';
import { inQuietWindow, localHHMM, nextQuietTo } from '../_shared/notify-util.ts';

const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

function isServiceCall(req: Request): boolean {
  if (req.headers.get('Authorization') === `Bearer ${SERVICE_KEY}`) return true;
  const cronSecret = Deno.env.get('CRON_SECRET');
  return !!cronSecret && req.headers.get('x-cron-secret') === cronSecret;
}

function apnsConfig(): ApnsConfig | null {
  const keyId = Deno.env.get('APNS_KEY_ID');
  const teamId = Deno.env.get('APNS_TEAM_ID');
  const privateKey = Deno.env.get('APNS_PRIVATE_KEY');
  const bundleId = Deno.env.get('APNS_BUNDLE_ID');
  if (!keyId || !teamId || !privateKey || !bundleId) return null;
  return { keyId, teamId, privateKey, bundleId, production: Deno.env.get('APNS_PRODUCTION') === 'true' };
}

/** Tidszonen kommer från telefonen; en okänd zon får standardzonen i stället för att stoppa notisen. */
function validTimeZone(zone: string): string {
  try {
    new Intl.DateTimeFormat('sv-SE', { timeZone: zone });
    return zone;
  } catch {
    return 'Europe/Stockholm';
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (!isServiceCall(req)) return json({ error: 'forbidden' }, 401);
  const svc = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY, { auth: { persistSession: false } });
  const now = new Date().toISOString();

  const { data: rows, error } = await svc
    .from('notification_queue')
    .select('id, recipient, activity:activity_log(type, actor, entity_id, payload)')
    .is('sent_at', null)
    .lte('send_after', now)
    .order('id');
  if (error) return json({ error: error.message }, 500);
  if (!rows?.length) return json({ sent: 0 });

  const byRecipient = new Map<string, typeof rows>();
  for (const row of rows) byRecipient.set(row.recipient, [...(byRecipient.get(row.recipient) ?? []), row]);

  const config = apnsConfig();
  const report: unknown[] = [];
  for (const [recipient, group] of byRecipient) {
    const ids = group.map((g) => g.id);
    const { data: prefs } = await svc
      .from('notification_prefs')
      .select('quiet_enabled, quiet_from, quiet_to, time_zone')
      .eq('user_id', recipient)
      .maybeSingle();
    if (prefs?.quiet_enabled) {
      const zone = validTimeZone(prefs.time_zone);
      if (inQuietWindow(localHHMM(new Date(now), zone), prefs.quiet_from, prefs.quiet_to)) {
        const deferredTo = nextQuietTo(new Date(now), prefs.quiet_to, zone);
        await svc.from('notification_queue').update({ send_after: deferredTo }).in('id', ids);
        report.push({ recipient, deferredTo });
        continue;
      }
    }

    const acts = group.map((g) => {
      const a = Array.isArray(g.activity) ? g.activity[0] : g.activity;
      return { type: a.type as string, entity_id: String(a.entity_id), payload: a.payload, actor: a.actor as string };
    });
    // Hushållen har två medlemmar, så allt i mottagarens kö kommer från partnern.
    const { data: actor } = await svc.from('profiles').select('name').eq('id', acts[0].actor).maybeSingle();
    const digest = buildDigest(actor?.name ?? 'Din partner', acts);

    if (digest) {
      const { data: devices } = await svc.from('device_tokens').select('token').eq('user_id', recipient);
      for (const { token } of devices ?? []) {
        if (!config) {
          report.push({ recipient, token, ...digest, dryRun: true });
          continue;
        }
        const result = await sendApns(config, token, digest);
        report.push({ recipient, status: result.status, reason: result.reason });
        if (result.unregistered) await svc.from('device_tokens').delete().eq('token', token);
      }
    }
    await svc.from('notification_queue').update({ sent_at: now }).in('id', ids);
  }
  return json({ dryRun: !config, notifications: report });
});
