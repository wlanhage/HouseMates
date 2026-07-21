/**
 * Spegel av shopping/todos/activity i IndexedDB (spec §12.3).
 * hydrateFromMirror() fyller storarna direkt vid start (offline-first).
 * startMirrorSync() speglar därefter varje storeändring (även optimistiska),
 * så appen visar rätt läge även om den öppnas offline igen.
 */
import { getDB } from './idb';
import { shopping, todosOpen, todosDone, activity, events } from './stores';
import type { ShoppingItem, Todo, Activity, CalendarEvent } from '$lib/types';

type MirrorKey = 'shopping' | 'todosOpen' | 'todosDone' | 'activity' | 'events';

async function put(key: MirrorKey, value: unknown): Promise<void> {
  try {
    const db = await getDB();
    await db.put('cache', value, key);
  } catch {
    /* IndexedDB kan saknas (privat läge) – nätet är källan ändå */
  }
}

async function read<T>(key: MirrorKey): Promise<T | undefined> {
  try {
    const db = await getDB();
    return (await db.get('cache', key)) as T | undefined;
  } catch {
    return undefined;
  }
}

/** Fyll storarna ur spegeln direkt vid start (innan nätverket svarar). */
export async function hydrateFromMirror(): Promise<void> {
  const [s, to, td, a, ev] = await Promise.all([
    read<ShoppingItem[]>('shopping'),
    read<Todo[]>('todosOpen'),
    read<Todo[]>('todosDone'),
    read<Activity[]>('activity'),
    read<CalendarEvent[]>('events')
  ]);
  if (s) shopping.set(s);
  if (to) todosOpen.set(to);
  if (td) todosDone.set(td);
  if (a) activity.set(a);
  if (ev) events.set(ev);
}

const timers = new Map<MirrorKey, ReturnType<typeof setTimeout>>();
function saveDebounced(key: MirrorKey, value: unknown): void {
  clearTimeout(timers.get(key));
  timers.set(
    key,
    setTimeout(() => void put(key, value), 250)
  );
}

/** Spegla varje storeändring till IndexedDB. Anropa EFTER hydrateFromMirror. */
export function startMirrorSync(): () => void {
  const unsubs = [
    shopping.subscribe((v) => saveDebounced('shopping', v)),
    todosOpen.subscribe((v) => saveDebounced('todosOpen', v)),
    todosDone.subscribe((v) => saveDebounced('todosDone', v)),
    activity.subscribe((v) => saveDebounced('activity', v)),
    events.subscribe((v) => saveDebounced('events', v))
  ];
  return () => unsubs.forEach((u) => u());
}
