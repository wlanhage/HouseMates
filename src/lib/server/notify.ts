/**
 * Notis-worker (spec §11). Plockar förfallna, osända notification_queue-rader
 * per mottagare, respekterar tysta timmar + prefs, bygger EN digest och skickar
 * via web-push. Ren logik ligger i notify-util.ts (testad §15).
 */
import webpush from 'web-push';
import { env } from '$env/dynamic/private';
import { db, now } from './db';
import { inQuietWindow, summarizeActivities, nextQuietTo, localHHMM } from './notify-util';

const TZ = env.TZ_DEFAULT ?? 'Europe/Stockholm';

let vapidReady = false;
function ensureVapid(): boolean {
  if (vapidReady) return true;
  const pub = env.VAPID_PUBLIC_KEY;
  const priv = env.VAPID_PRIVATE_KEY;
  if (!pub || !priv) return false;
  webpush.setVapidDetails(env.VAPID_SUBJECT ?? 'mailto:dev@example.com', pub, priv);
  vapidReady = true;
  return true;
}

interface QueueRow {
  id: number;
  recipient: string;
  type: string;
  actor: string;
  payload: string | null;
  created_at: string;
}

export async function runNotifyWorker(): Promise<void> {
  const nowDate = new Date();
  const rows = db
    .prepare(
      `SELECT nq.id, nq.recipient, al.type, al.actor, al.payload, al.created_at
       FROM notification_queue nq JOIN activity_log al ON al.id = nq.activity_id
       WHERE nq.sent_at IS NULL AND nq.send_after <= ?
       ORDER BY nq.recipient, al.created_at`
    )
    .all(nowDate.toISOString()) as QueueRow[];
  if (rows.length === 0) return;

  const byRecipient = new Map<string, QueueRow[]>();
  for (const r of rows) {
    const list = byRecipient.get(r.recipient) ?? [];
    list.push(r);
    byRecipient.set(r.recipient, list);
  }

  const markSent = db.prepare('UPDATE notification_queue SET sent_at = ? WHERE id = ?');
  const deferRow = db.prepare('UPDATE notification_queue SET send_after = ? WHERE id = ?');

  for (const [recipient, group] of byRecipient) {
    const prefs = db
      .prepare('SELECT enabled, quiet_from, quiet_to FROM notification_prefs WHERE user_id = ?')
      .get(recipient) as { enabled: number; quiet_from: string; quiet_to: string } | undefined;

    if (!prefs || prefs.enabled === 0) {
      for (const r of group) markSent.run(now(), r.id);
      continue;
    }

    if (inQuietWindow(localHHMM(nowDate, TZ), prefs.quiet_from, prefs.quiet_to)) {
      const deferTo = nextQuietTo(nowDate, prefs.quiet_to, TZ);
      for (const r of group) deferRow.run(deferTo, r.id);
      continue;
    }

    const subs = db
      .prepare(
        'SELECT id, endpoint, p256dh, auth FROM push_subscriptions WHERE user_id = ? AND failed_at IS NULL'
      )
      .all(recipient) as { id: number; endpoint: string; p256dh: string; auth: string }[];

    if (subs.length === 0 || !ensureVapid()) {
      for (const r of group) markSent.run(now(), r.id);
      continue;
    }

    const actorName =
      (db.prepare('SELECT name FROM users WHERE id = ?').get(group[0].actor) as { name: string } | undefined)
        ?.name.replace(/\s*\(test\)/, '') ?? 'Någon';

    const body = summarizeActivities(
      group.map((r) => ({ type: r.type, payload: r.payload ? JSON.parse(r.payload) : null }))
    );
    const payload = JSON.stringify({ title: actorName, body });

    for (const sub of subs) {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload
        );
      } catch (err) {
        const code = (err as { statusCode?: number }).statusCode;
        if (code === 404 || code === 410) {
          db.prepare('UPDATE push_subscriptions SET failed_at = ? WHERE id = ?').run(now(), sub.id);
        }
      }
    }
    for (const r of group) markSent.run(now(), r.id);
  }
}
