import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';
import { ok } from '$lib/server/http';
import { db } from '$lib/server/db';
import type { NotificationPrefs, SyncStatus, User } from '$lib/types';

const selPartner = db.prepare<[string]>('SELECT id, name, color FROM users WHERE id != ? LIMIT 1');
const selPrefs = db.prepare<[string]>(
  'SELECT enabled, quiet_from, quiet_to, digest_minutes FROM notification_prefs WHERE user_id = ?'
);
const selSync = db.prepare<[string]>(
  'SELECT last_synced_at, failing_since, last_error FROM sync_state WHERE user_id = ?'
);

export const GET: RequestHandler = async ({ locals }) => {
  const user = locals.user!; // garanterat av hooks-guarden
  const partner = (selPartner.get(user.id) as User | undefined) ?? null;

  const prefsRow = selPrefs.get(user.id) as
    | { enabled: number; quiet_from: string; quiet_to: string; digest_minutes: number }
    | undefined;
  const prefs: NotificationPrefs = prefsRow
    ? {
        enabled: prefsRow.enabled === 1,
        quiet_from: prefsRow.quiet_from,
        quiet_to: prefsRow.quiet_to,
        digest_minutes: prefsRow.digest_minutes
      }
    : { enabled: true, quiet_from: '21:00', quiet_to: '07:30', digest_minutes: 10 };

  const syncRow = selSync.get(user.id) as SyncStatus | undefined;
  const syncStatus: SyncStatus = syncRow ?? {
    last_synced_at: null,
    failing_since: null,
    last_error: null
  };

  return ok({ user, partner, prefs, syncStatus, vapidPublicKey: env.VAPID_PUBLIC_KEY ?? '' });
};
