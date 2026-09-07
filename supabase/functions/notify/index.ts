/**
 * Notis-worker (spec §11): körs varje minut via pg_cron. Plockar förfallna
 * orader ur notification_queue per mottagare, respekterar tysta timmar och
 * prefs, bygger EN digest och skickar via Web Push (VAPID).
 */
// @ts-expect-error jsr-import i Deno
import * as webpush from 'jsr:@negrel/webpush@0.3.0';
import {
  serviceClient,
  jsonResponse,
  handleOptions,
  isServiceCall,
  requireMember,
  HttpError
} from '../_shared/util.ts';
import { buildDigest } from '../_shared/digest.ts';

const TZ = Deno.env.get('TZ_DEFAULT') ?? 'Europe/Stockholm';

// ── Ren logik (speglar src/lib/server/notify-util.ts, testad i vitest) ──
const toMin = (hhmm: string): number => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};

export function inQuietWindow(hhmm: string, from: string, to: string): boolean {
  const t = toMin(hhmm);
  const f = toMin(from);
  const e = toMin(to);
  if (f === e) return false;
  if (f < e) return t >= f && t < e;
  return t >= f || t < e;
}

function localHHMM(date: Date): string {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: TZ,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }).format(date);
}

export function nextQuietTo(after: Date, quietTo: string, tz = TZ): string {
  const [yy, mm, dd] = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })
    .format(after)
    .split('-')
    .map(Number);
  const [qh, qm] = quietTo.split(':').map(Number);
  const wallToUtc = (y: number, m: number, d: number): Date => {
    const guess = Date.UTC(y, m - 1, d, qh, qm);
    const p = Object.fromEntries(
      new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        hour12: false,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
      })
        .formatToParts(new Date(guess))
        .map((x) => [x.type, x.value])
    );
    const hour = p.hour === '24' ? 0 : Number(p.hour);
    const asUtc = Date.UTC(
      Number(p.year),
      Number(p.month) - 1,
      Number(p.day),
      hour,
      Number(p.minute),
      Number(p.second)
    );
    return new Date(guess - (asUtc - guess));
  };
  let candidate = wallToUtc(yy, mm, dd);
  if (candidate.getTime() <= after.getTime()) {
    const next = new Date(Date.UTC(yy, mm - 1, dd + 1));
    candidate = wallToUtc(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate());
  }
  return candidate.toISOString();
}

// ── Worker ───────────────────────────────────────────────────
let appServer: unknown = null;
async function getAppServer(): Promise<any | null> {
  if (appServer) return appServer;
  const keysJson = Deno.env.get('VAPID_KEYS_JSON');
  if (!keysJson) return null;
  const vapidKeys = await webpush.importVapidKeys(JSON.parse(keysJson), { extractable: false });
  appServer = await webpush.ApplicationServer.new({
    contactInformation: Deno.env.get('VAPID_SUBJECT') ?? 'mailto:planeraren@example.com',
    vapidKeys
  });
  return appServer;
}

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    if (!isServiceCall(req)) await requireMember(req);
    const svc = serviceClient();
    const now = new Date();

    const { data: rows } = await svc
      .from('notification_queue')
      .select('id, recipient, send_after, activity:activity_log(type, actor, entity_id, payload, created_at)')
      .is('sent_at', null)
      .lte('send_after', now.toISOString())
      .order('id');
    if (!rows?.length) return jsonResponse({ sent: 0 });

    const byRecipient = new Map<string, typeof rows>();
    for (const r of rows) {
      const list = byRecipient.get(r.recipient) ?? [];
      list.push(r);
      byRecipient.set(r.recipient, list);
    }

    let sentCount = 0;
    for (const [recipient, group] of byRecipient) {
      const ids = group.map((g) => g.id);
      const { data: prefs } = await svc
        .from('notification_prefs')
        .select('*')
        .eq('username', recipient)
        .maybeSingle();

      if (!prefs || !prefs.enabled) {
        await svc.from('notification_queue').update({ sent_at: now.toISOString() }).in('id', ids);
        continue;
      }

      if (inQuietWindow(localHHMM(now), prefs.quiet_from, prefs.quiet_to)) {
        const deferTo = nextQuietTo(now, prefs.quiet_to);
        await svc.from('notification_queue').update({ send_after: deferTo }).in('id', ids);
        continue;
      }

      const { data: subs } = await svc
        .from('push_subscriptions')
        .select('*')
        .eq('username', recipient)
        .is('failed_at', null);

      const server = await getAppServer();
      if (!subs?.length || !server) {
        await svc.from('notification_queue').update({ sent_at: now.toISOString() }).in('id', ids);
        continue;
      }

      const acts = group.map((g) => {
        const a = Array.isArray(g.activity) ? g.activity[0] : g.activity;
        return {
          type: a.type as string,
          entity_id: String(a.entity_id ?? ''),
          payload: a.payload as Record<string, unknown> | null,
          actor: a.actor as string
        };
      });
      const { data: actorProfile } = await svc
        .from('profiles')
        .select('name')
        .eq('username', acts[0].actor)
        .maybeSingle();
      const actorName = (actorProfile?.name ?? 'Någon').replace(/\s*\(test\)/, '');
      const digest = buildDigest(actorName, acts);
      if (!digest) {
        // Allt nettades bort (t.ex. bockat och avbockat) – inget att berätta.
        await svc.from('notification_queue').update({ sent_at: now.toISOString() }).in('id', ids);
        continue;
      }
      const payload = JSON.stringify(digest);

      for (const sub of subs) {
        try {
          const subscriber = server.subscribe({
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth }
          });
          await subscriber.pushTextMessage(payload, {});
          sentCount++;
        } catch (err) {
          const status = (err as { response?: { status?: number } })?.response?.status;
          if (status === 404 || status === 410) {
            await svc
              .from('push_subscriptions')
              .update({ failed_at: now.toISOString() })
              .eq('id', sub.id);
          }
        }
      }
      await svc.from('notification_queue').update({ sent_at: now.toISOString() }).in('id', ids);
    }
    return jsonResponse({ sent: sentCount });
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
