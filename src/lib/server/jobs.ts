/**
 * Bakgrundsjobb (spec §13). Startas EN gång från hooks.server.ts.
 * Jobb registreras milstolpe för milstolpe:
 *   - CalDAV-synk (M4)          – var SYNC_INTERVAL_MINUTES minut
 *   - Notis-worker (M6)         – varje minut
 *   - Städning (M2+)            – dagligen 04:00
 *   - Sessionsstäd              – dagligen 04:10
 *
 * Varje jobb får en isRunning-flagga så de inte överlappar sig själva.
 */
import cron from 'node-cron';
import { env } from '$env/dynamic/private';
import { db } from './db';
import { syncAll } from './caldav/sync';
import { runNotifyWorker } from './notify';

const g = globalThis as unknown as { __planeraren_jobs_started?: boolean };

/** Kör ett jobb som inte överlappar sig självt. */
export function guarded(fn: () => void | Promise<void>): () => Promise<void> {
  let running = false;
  return async () => {
    if (running) return;
    running = true;
    try {
      await fn();
    } catch (err) {
      console.error('[jobs] fel:', err);
    } finally {
      running = false;
    }
  };
}

export function startBackgroundJobs(): void {
  if (g.__planeraren_jobs_started) return;
  g.__planeraren_jobs_started = true;

  // Städning: hård radering av gamla soft-deletes m.m. (spec schema-slutkommentar).
  const cleanup = guarded(() => {
    const stmts = [
      "DELETE FROM shopping_items WHERE deleted_at IS NOT NULL AND deleted_at < datetime('now','-30 days')",
      "DELETE FROM todos WHERE deleted_at IS NOT NULL AND deleted_at < datetime('now','-30 days')",
      "DELETE FROM events WHERE deleted_at IS NOT NULL AND deleted_at < datetime('now','-30 days')",
      "DELETE FROM todos WHERE done = 1 AND done_at IS NOT NULL AND done_at < datetime('now','-30 days')",
      "DELETE FROM notification_queue WHERE sent_at IS NOT NULL AND sent_at < datetime('now','-7 days')",
      "DELETE FROM push_subscriptions WHERE failed_at IS NOT NULL AND failed_at < datetime('now','-7 days')"
    ];
    const run = db.transaction(() => stmts.forEach((s) => db.prepare(s).run()));
    run();
  });
  cron.schedule('0 4 * * *', cleanup, { timezone: 'Europe/Stockholm' });

  // Sessionsstäd 04:10.
  const sessionCleanup = guarded(() => {
    db.prepare("DELETE FROM sessions WHERE expires_at < datetime('now')").run();
  });
  cron.schedule('10 4 * * *', sessionCleanup, { timezone: 'Europe/Stockholm' });

  // CalDAV-synk var SYNC_INTERVAL_MINUTES minut (spec §9.2).
  const interval = Math.max(1, Number(env.SYNC_INTERVAL_MINUTES ?? '5'));
  const sync = guarded(() => syncAll());
  cron.schedule(`*/${interval} * * * *`, sync);
  // Kör en runda strax efter start så cachen fylls direkt.
  setTimeout(() => void sync(), 3000);

  // Notis-worker varje minut (spec §11).
  const notify = guarded(() => runNotifyWorker());
  cron.schedule('* * * * *', notify);
}

/** Trigga en synkrunda direkt (pull-to-refresh, dev). */
export { syncAll as runSyncNow } from './caldav/sync';
