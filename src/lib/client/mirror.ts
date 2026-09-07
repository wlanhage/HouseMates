/**
 * Spegel av shopping/todos/activity i IndexedDB (spec §12.3).
 * hydrateFromMirror() fyller storarna direkt vid start (offline-first).
 * startMirrorSync() speglar därefter varje storeändring (även optimistiska),
 * så appen visar rätt läge även om den öppnas offline igen.
 */
import { getDB } from './idb';
import { shopping, todosOpen, todosDone, chores, favorites, activity, events } from './stores';
import type { ShoppingItem, Todo, Chore, Favorite, Activity, CalendarEvent } from '$lib/types';

type MirrorKey = 'shopping' | 'todosOpen' | 'todosDone' | 'chores' | 'favorites' | 'activity' | 'events';

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
  const [s, to, td, ch, fa, a, ev] = await Promise.all([
    read<ShoppingItem[]>('shopping'),
    read<Todo[]>('todosOpen'),
    read<Todo[]>('todosDone'),
    read<Chore[]>('chores'),
    read<Favorite[]>('favorites'),
    read<Activity[]>('activity'),
    read<CalendarEvent[]>('events')
  ]);
  if (s) shopping.set(s);
  if (to) todosOpen.set(to);
  if (td) todosDone.set(td);
  if (ch) chores.set(ch);
  if (fa) favorites.set(fa);
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
    chores.subscribe((v) => saveDebounced('chores', v)),
    favorites.subscribe((v) => saveDebounced('favorites', v)),
    activity.subscribe((v) => saveDebounced('activity', v)),
    events.subscribe((v) => saveDebounced('events', v))
  ];
  return () => unsubs.forEach((u) => u());
}
