import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok } from '$lib/server/http';
import type { SyncStatus } from '$lib/types';

export const GET: RequestHandler = ({ locals }) => {
  const row = db
    .prepare('SELECT last_synced_at, failing_since, last_error FROM sync_state WHERE user_id = ?')
    .get(locals.user!.id) as SyncStatus | undefined;
  return ok(row ?? { last_synced_at: null, failing_since: null, last_error: null });
};
