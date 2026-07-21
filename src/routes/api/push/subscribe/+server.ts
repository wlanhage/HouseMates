import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok, catchHttp, readJson } from '$lib/server/http';

interface Sub {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const b = await readJson<Sub>(request);
    db.prepare(
      `INSERT INTO push_subscriptions (user_id, endpoint, p256dh, auth)
       VALUES (?, ?, ?, ?)
       ON CONFLICT(endpoint) DO UPDATE SET user_id = excluded.user_id,
         p256dh = excluded.p256dh, auth = excluded.auth, failed_at = NULL`
    ).run(locals.user!.id, b.endpoint, b.keys.p256dh, b.keys.auth);
    return ok({ ok: true });
  } catch (e) {
    return catchHttp(e);
  }
};

export const DELETE: RequestHandler = async ({ request, locals }) => {
  try {
    const { endpoint } = await readJson<{ endpoint: string }>(request);
    db.prepare('DELETE FROM push_subscriptions WHERE endpoint = ? AND user_id = ?').run(
      endpoint,
      locals.user!.id
    );
    return ok({ ok: true });
  } catch (e) {
    return catchHttp(e);
  }
};
