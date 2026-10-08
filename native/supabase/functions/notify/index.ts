/**
 * Notis-worker: körs varje minut via pg_cron (../../cron.sql). Tar förfallna rader ur
 * notification_queue per mottagare, bygger EN digest och skickar via APNs.
 * Under mottagarens tysta timmar skjuts raderna upp till när de tar slut.
 *
 * Raderna tas (sent_at sätts) i samma anrop som de hämtas, så att två körningar som överlappar
 * aldrig skickar samma notis. Går sändningen inte fram (Apple svarar inte, för många anrop,
 * ett oväntat fel) släpps raderna och försöks igen nästa minut.
 *
 * Utan APNs-nyckel körs den bara torrt om NOTIFY_DRY_RUN=true (lokalt); annars rörs kön inte,
 * så att en saknad nyckel i produktion inte kastar alla notiser.
 */
// @ts-expect-error npm-import i Deno
import { createClient } from 'npm:@supabase/supabase-js@2';
import { buildDigest } from '../_shared/digest.ts';
import { sendApns, type ApnsConfig, type ApnsMessage, type ApnsResult } from '../_shared/apns.ts';
import { inQuietWindow, localHHMM, nextQuietTo } from '../_shared/notify-util.ts';

const SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/** Jämför i konstant tid, så att svarstiden inte avslöjar hur mycket av hemligheten som stämde. */
function sameSecret(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected || given.length !== expected.length) return false;
  let difference = 0;
  for (let i = 0; i < given.length; i++) difference |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return difference === 0;
}

function isServiceCall(req: Request): boolean {
  return (
    sameSecret(req.headers.get('Authorization'), `Bearer ${SERVICE_KEY}`) ||
    sameSecret(req.headers.get('x-cron-secret'), Deno.env.get('CRON_SECRET'))
  );
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

/**
 * Byggen från Xcode har tokens för Apples testmiljö, TestFlight och App Store för den riktiga.
 * Svarar den ena miljön att tokenen är fel provas den andra innan tokenen räknas som ogiltig.
 */
async function send(config: ApnsConfig, token: string, message: ApnsMessage): Promise<ApnsResult> {
  const result = await sendApns(config, token, message);
  if (result.reason !== 'BadDeviceToken') return result;
  return sendApns({ ...config, production: !config.production }, token, message);
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (!isServiceCall(req)) return json({ error: 'forbidden' }, 401);
  const config = apnsConfig();
  const dryRun = !config && Deno.env.get('NOTIFY_DRY_RUN') === 'true';
  if (!config && !dryRun) return json({ error: 'APNs saknas: sätt APNS_* (eller NOTIFY_DRY_RUN=true lokalt)' }, 500);

  const svc = createClient(Deno.env.get('SUPABASE_URL')!, SERVICE_KEY, { auth: { persistSession: false } });
  const now = new Date().toISOString();

  const { data: rows, error } = await svc
    .from('notification_queue')
    .update({ sent_at: now })
    .is('sent_at', null)
    .lte('send_after', now)
    .select('id, recipient, activity:activity_log(type, actor, entity_id, payload)');
  if (error) return json({ error: error.message }, 500);
  if (!rows?.length) return json({ sent: 0 });

  const byRecipient = new Map<string, typeof rows>();
  for (const row of [...rows].sort((a, b) => a.id - b.id)) {
    byRecipient.set(row.recipient, [...(byRecipient.get(row.recipient) ?? []), row]);
  }

  /** Lägger tillbaka raderna i kön, eventuellt till en senare tid. */
  const release = (ids: number[], sendAfter?: string) =>
    svc
      .from('notification_queue')
      .update(sendAfter ? { sent_at: null, send_after: sendAfter } : { sent_at: null })
      .in('id', ids);

  const report: unknown[] = [];
  for (const [recipient, group] of byRecipient) {
    const ids = group.map((g) => g.id);
    try {
      const { data: prefs } = await svc
        .from('notification_prefs')
        .select('quiet_enabled, quiet_from, quiet_to, time_zone')
        .eq('user_id', recipient)
        .maybeSingle();
      if (prefs?.quiet_enabled) {
        const zone = validTimeZone(prefs.time_zone);
        if (inQuietWindow(localHHMM(new Date(now), zone), prefs.quiet_from, prefs.quiet_to)) {
          const deferredTo = nextQuietTo(new Date(now), prefs.quiet_to, zone);
          await release(ids, deferredTo);
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
      if (!digest) continue;

      const { data: devices } = await svc.from('device_tokens').select('token').eq('user_id', recipient);
      let delivered = false;
      let worthRetrying = false;
      for (const { token } of devices ?? []) {
        if (!config) {
          report.push({ recipient, token, ...digest, dryRun: true });
          continue;
        }
        const result = await send(config, token, digest);
        report.push({ recipient, status: result.status, reason: result.reason });
        if (result.status < 300) delivered = true;
        else if (result.unregistered) await svc.from('device_tokens').delete().eq('token', token);
        else if (result.status === 429 || result.status >= 500) worthRetrying = true;
      }
      // Kom notisen fram till någon telefon skickas den inte igen; annars nästa minut.
      if (worthRetrying && !delivered) await release(ids);
    } catch (e) {
      await release(ids);
      report.push({ recipient, error: String(e) });
    }
  }
  return json({ dryRun, notifications: report });
});
