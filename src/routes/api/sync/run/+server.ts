import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok, catchHttp } from '$lib/server/http';
import { runSyncNow } from '$lib/server/jobs';
import type { SyncStatus } from '$lib/types';

export const POST: RequestHandler = async ({ locals }) => {
  try {
    await runSyncNow();
    const row = db
      .prepare('SELECT last_synced_at, failing_since, last_error FROM sync_state WHERE user_id = ?')
      .get(locals.user!.id) as SyncStatus | undefined;
    return ok(row ?? { last_synced_at: null, failing_since: null, last_error: null });
  } catch (e) {
    return catchHttp(e);
  }
};
