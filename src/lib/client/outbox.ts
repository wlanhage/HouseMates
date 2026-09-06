/**
 * Mutationskö (offline). Operationer köas semantiskt ({op, ...}) och spelas
 * upp FIFO mot Supabase vid reconnect. Idempotens via klient-uuid: insert med
 * samma id → 23505 → slängs (finns redan). Konfliktregel vid replay: datafel
 * (dubblett/versionskonflikt/validering) → släng, server vinner. Nätverksfel
 * → stanna kvar i kön.
 *
 * Eventmutationer köas ALDRIG (kalendern kräver nät, spec §7.5).
 */
import { getDB } from './idb';
import { supabase } from './supabase';

export type OutboxOp =
  | { op: 'shopping.insert'; row: { id: string; name: string; qty?: string | null } }
  | { op: 'shopping.update'; id: string; version: number; patch: Record<string, unknown> }
  | { op: 'shopping.archive' }
  | { op: 'shopping.unarchive'; ids: string[] }
  | { op: 'todos.insert'; row: Record<string, unknown> }
  | { op: 'todos.update'; id: string; version: number; patch: Record<string, unknown> }
  | { op: 'chores.insert'; row: Record<string, unknown> }
  | { op: 'chores.update'; id: string; version: number; patch: Record<string, unknown> };

interface QueueEntry {
  seq?: number;
  entry: OutboxOp;
}

function isNetworkError(e: unknown): boolean {
  // supabase-js: transportfel blir TypeError ("Failed to fetch" m.fl.),
  // PostgREST-datafel har .code (t.ex. '23505').
  if (typeof e === 'object' && e !== null && 'code' in e) return false;
  const msg = e instanceof Error ? e.message : String(e);
  return /fetch|network|load failed|timeout/i.test(msg);
}

/** Utför en operation mot Supabase. Kastar vid fel. */
export async function executeOp(op: OutboxOp): Promise<void> {
  switch (op.op) {
    case 'shopping.insert': {
      // created_by sätts av trigger (my_username) – värdet här är bara ett
      // giltigt FK-fallback och används aldrig när requesten är autentiserad.
      const { error } = await supabase
        .from('shopping_items')
        .insert({ id: op.row.id, name: op.row.name, qty: op.row.qty ?? null });
      if (error) throw error;
      return;
    }
    case 'shopping.update': {
      const { error } = await supabase
        .from('shopping_items')
        .update(op.patch)
        .eq('id', op.id)
        .eq('version', op.version);
      if (error) throw error;
      return;
    }
    case 'shopping.archive': {
      const { error } = await supabase.rpc('archive_checked');
      if (error) throw error;
      return;
    }
    case 'shopping.unarchive': {
      const { error } = await supabase.rpc('unarchive', { p_ids: op.ids });
      if (error) throw error;
      return;
    }
    case 'todos.insert': {
      const { error } = await supabase.from('todos').insert(op.row);
      if (error) throw error;
      return;
    }
    case 'todos.update': {
      const { error } = await supabase
        .from('todos')
        .update(op.patch)
        .eq('id', op.id)
        .eq('version', op.version);
      if (error) throw error;
      return;
    }
    case 'chores.insert': {
      const { error } = await supabase.from('chores').insert(op.row);
      if (error) throw error;
      return;
    }
    case 'chores.update': {
      const { error } = await supabase
        .from('chores')
        .update(op.patch)
        .eq('id', op.id)
        .eq('version', op.version);
      if (error) throw error;
      return;
    }
  }
}

async function enqueue(op: OutboxOp): Promise<void> {
  const db = await getDB();
  await db.add('outbox', { entry: op } as never);
}

export interface SendResult {
  sent: boolean; // false = köad (offline/nätverksfel)
  error?: unknown; // datafel (ej nätverk) – hanteras av anroparen
}

/** Kör nu om online; offline/nätverksfel → köa. Datafel returneras. */
export async function sendOp(op: OutboxOp): Promise<SendResult> {
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    await enqueue(op);
    return { sent: false };
  }
  try {
    await executeOp(op);
    return { sent: true };
  } catch (e) {
    if (isNetworkError(e)) {
      await enqueue(op);
      return { sent: false };
    }
    return { sent: true, error: e };
  }
}

export type ReplayOutcome = 'sent' | 'dropped' | 'stop';

/** Ren beslutslogik för en köad operation (testbar). */
export async function replayOne(
  op: OutboxOp,
  exec: (op: OutboxOp) => Promise<void> = executeOp
): Promise<ReplayOutcome> {
  try {
    await exec(op);
    return 'sent';
  } catch (e) {
    if (isNetworkError(e)) return 'stop';
    return 'dropped'; // dubblett/konflikt/validering → server vinner
  }
}

let replaying = false;

export async function replayOutbox(): Promise<boolean> {
  if (replaying) return false;
  replaying = true;
  let changed = false;
  try {
    const db = await getDB();
    const entries = (await db.getAll('outbox')) as unknown as QueueEntry[];
    entries.sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0));
    for (const e of entries) {
      if (typeof navigator !== 'undefined' && !navigator.onLine) break;
      const outcome = await replayOne(e.entry);
      if (outcome === 'stop') break;
      await db.delete('outbox', e.seq!);
      changed = true;
    }
  } catch {
    /* IndexedDB saknas – ignorera */
  } finally {
    replaying = false;
  }
  return changed;
}
