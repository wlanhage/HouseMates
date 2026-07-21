import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok, catchHttp, readJson } from '$lib/server/http';

const HHMM = /^\d{2}:\d{2}$/;

export const PATCH: RequestHandler = async ({ request, locals }) => {
  try {
    const b = await readJson<{
      enabled?: boolean;
      quiet_from?: string;
      quiet_to?: string;
      digest_minutes?: number;
    }>(request);

    const sets: string[] = [];
    const vals: unknown[] = [];
    if (b.enabled !== undefined) {
      sets.push('enabled = ?');
      vals.push(b.enabled ? 1 : 0);
    }
    if (b.quiet_from !== undefined && HHMM.test(b.quiet_from)) {
      sets.push('quiet_from = ?');
      vals.push(b.quiet_from);
    }
    if (b.quiet_to !== undefined && HHMM.test(b.quiet_to)) {
      sets.push('quiet_to = ?');
      vals.push(b.quiet_to);
    }
    if (b.digest_minutes !== undefined && Number.isFinite(b.digest_minutes)) {
      sets.push('digest_minutes = ?');
      vals.push(Math.max(0, Math.min(120, Math.round(b.digest_minutes))));
    }
    if (sets.length) {
      vals.push(locals.user!.id);
      db.prepare(`UPDATE notification_prefs SET ${sets.join(', ')} WHERE user_id = ?`).run(...vals);
    }

    const prefs = db
      .prepare('SELECT enabled, quiet_from, quiet_to, digest_minutes FROM notification_prefs WHERE user_id = ?')
      .get(locals.user!.id) as {
      enabled: number;
      quiet_from: string;
      quiet_to: string;
      digest_minutes: number;
    };
    return ok({ ...prefs, enabled: prefs.enabled === 1 });
  } catch (e) {
    return catchHttp(e);
  }
};
