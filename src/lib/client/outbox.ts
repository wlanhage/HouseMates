/**
 * Mutationskö (spec §12.3). Offline (eller vid nätverksfel) läggs mutationen i
 * IndexedDB och spelas upp FIFO vid reconnect. Idempotens via klient-uuid gör
 * dubbelreplay ofarlig. Konfliktregel vid replay: 4xx (409/duplicate/
 * version_conflict) → släng mutationen, server vinner. Nätverksfel → stoppa.
 *
 * Eventmutationer går ALDRIG i kön (spec §7.5) – de använder api-lagret direkt.
 */
import { getDB } from './idb';
import { apiPost, apiPatch, apiDelete, ApiError } from './api';

export interface Mutation {
  method: 'POST' | 'PATCH' | 'DELETE';
  path: string;
  body?: unknown;
  entity: 'shopping' | 'todos';
}

async function rawSend<T>(m: Mutation): Promise<T> {
  if (m.method === 'POST') return apiPost<T>(m.path, m.body);
  if (m.method === 'PATCH') return apiPatch<T>(m.path, m.body);
  return apiDelete<T>(m.path, m.body);
}

async function enqueue(m: Mutation): Promise<void> {
  const db = await getDB();
  await db.add('outbox', m);
}

/** Resultat av ett mutationsförsök: data (skickat) eller queued (i kön). */
export interface SendResult<T> {
  data?: T;
  queued?: boolean;
}

/** Skicka nu om online, annars köa. Nätverksfel → köa. 4xx kastas vidare. */
export async function sendMutation<T>(m: Mutation): Promise<SendResult<T>> {
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    await enqueue(m);
    return { queued: true };
  }
  try {
    const data = await rawSend<T>(m);
    return { data };
  } catch (e) {
    if (e instanceof ApiError && e.code === 'network') {
      await enqueue(m);
      return { queued: true };
    }
    throw e;
  }
}

export type ReplayOutcome = 'sent' | 'dropped' | 'stop';

/** Ren beslutslogik för en köad mutation (testbar utan IndexedDB). */
export async function replayOne(
  m: Mutation,
  send: (m: Mutation) => Promise<unknown> = rawSend
): Promise<ReplayOutcome> {
  try {
    await send(m);
    return 'sent';
  } catch (e) {
    if (e instanceof ApiError && e.code === 'network') return 'stop';
    // Alla 4xx (409/duplicate/version_conflict m.fl.) → server vinner, släng.
    return 'dropped';
  }
}

let replaying = false;

/** Spela upp hela kön FIFO. Returnerar true om något skickades/slängdes. */
export async function replayOutbox(): Promise<boolean> {
  if (replaying) return false;
  replaying = true;
  let changed = false;
  try {
    const db = await getDB();
    const entries = await db.getAll('outbox');
    entries.sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0));
    for (const entry of entries) {
      if (typeof navigator !== 'undefined' && !navigator.onLine) break;
      const outcome = await replayOne(entry);
      if (outcome === 'stop') break;
      await db.delete('outbox', entry.seq!);
      changed = true;
    }
  } catch {
    /* IndexedDB otillgänglig – ignorera */
  } finally {
    replaying = false;
  }
  return changed;
}

export async function outboxCount(): Promise<number> {
  try {
    const db = await getDB();
    return db.count('outbox');
  } catch {
    return 0;
  }
}
