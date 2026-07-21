/**
 * logActivity() – anropas i SAMMA transaktion som varje mutation (spec §7.1, §8).
 * Skriver en rad i activity_log OCH köar en notis till den ANDRA användaren
 * (notification_queue, send_after = now + mottagarens digest_minutes).
 *
 * Notis-workern som faktiskt skickar push byggs i M6; här skapas bara raderna.
 * SSE-broadcast görs separat i endpointen efter transaktionen (in-memory, ej DB).
 */
import type { Database } from 'better-sqlite3';
import { toIso } from './sqlite-util';

export type ActivityType =
  | 'shopping.added'
  | 'shopping.checked'
  | 'shopping.unchecked'
  | 'shopping.deleted'
  | 'shopping.restored'
  | 'shopping.archived'
  | 'todo.created'
  | 'todo.done'
  | 'todo.undone'
  | 'todo.deleted'
  | 'todo.restored'
  | 'event.created'
  | 'event.updated'
  | 'event.deleted'
  | 'event.restored';

export interface ActivityInput {
  type: ActivityType;
  actor: string;
  entityType: 'shopping' | 'todo' | 'event';
  entityId: string;
  payload?: Record<string, unknown>;
}

export function logActivity(db: Database, a: ActivityInput): number {
  const info = db
    .prepare(
      'INSERT INTO activity_log (type, actor, entity_type, entity_id, payload) VALUES (?, ?, ?, ?, ?)'
    )
    .run(a.type, a.actor, a.entityType, a.entityId, a.payload ? JSON.stringify(a.payload) : null);
  const activityId = Number(info.lastInsertRowid);

  // Köa notis till partnern (den enda andra användaren).
  const partner = db.prepare('SELECT id FROM users WHERE id != ? LIMIT 1').get(a.actor) as
    | { id: string }
    | undefined;
  if (partner) {
    const prefs = db
      .prepare('SELECT digest_minutes FROM notification_prefs WHERE user_id = ?')
      .get(partner.id) as { digest_minutes: number } | undefined;
    const digest = prefs?.digest_minutes ?? 10;
    const sendAfter = new Date(Date.now() + digest * 60_000).toISOString();
    db.prepare(
      'INSERT INTO notification_queue (recipient, activity_id, send_after) VALUES (?, ?, ?)'
    ).run(partner.id, activityId, sendAfter);
  }
  return activityId;
}

interface ActivityRow {
  id: number;
  type: string;
  actor: string;
  entity_type: 'shopping' | 'todo' | 'event';
  entity_id: string;
  payload: string | null;
  created_at: string;
}

/** Rårader ur activity_log, nyast först. Gruppering görs i klienten (spec §12.2). */
export function listActivity(db: Database, limit = 30, before?: number) {
  const rows = (
    before
      ? db
          .prepare('SELECT * FROM activity_log WHERE id < ? ORDER BY id DESC LIMIT ?')
          .all(before, limit)
      : db.prepare('SELECT * FROM activity_log ORDER BY id DESC LIMIT ?').all(limit)
  ) as ActivityRow[];
  return rows.map((r) => ({
    id: r.id,
    type: r.type,
    actor: r.actor,
    entity_type: r.entity_type,
    entity_id: r.entity_id,
    payload: r.payload ? (JSON.parse(r.payload) as Record<string, unknown>) : null,
    created_at: toIso(r.created_at)!
  }));
}
