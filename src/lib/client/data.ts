/**
 * Klientens "actions" – optimistiska mutationer mot storarna, via outbox
 * (offline-kö) mot Supabase, med återställning vid datafel + ångra-toast.
 *
 * Konflikthantering:
 *  - dubblett (23505) → hämta befintlig aktiv vara → "Fanns redan"
 *  - versionskonflikt → 0 uppdaterade rader → refetch ("server vinner")
 *  - kalender: aldrig offline-kö; edge function svarar 409 vid CalDAV-konflikt
 */
import { get } from 'svelte/store';
import { supabase } from './supabase';
import { sendOp } from './outbox';
import {
  shopping,
  todosOpen,
  todosDone,
  chores,
  favorites,
  activity,
  events,
  user,
  showToast,
  uuid
} from './stores';
import { ymd } from './dates';
import type {
  ShoppingItem,
  Todo,
  Chore,
  Favorite,
  ImportedRecipe,
  Activity,
  CalendarEvent
} from '$lib/types';
import { splitIngredient } from './ingredients';

const nowIso = () => new Date().toISOString();

function errMsg(e: unknown): string {
  if (typeof e === 'object' && e && 'message' in e) return 'Något gick fel.';
  return 'Något gick fel.';
}
const isDupe = (e: unknown): boolean =>
  typeof e === 'object' && e !== null && (e as { code?: string }).code === '23505';

function sortShopping(items: ShoppingItem[]): ShoppingItem[] {
  return [...items].sort(
    (a, b) => Number(a.checked) - Number(b.checked) || a.created_at.localeCompare(b.created_at)
  );
}
function sortTodosOpen(items: Todo[]): Todo[] {
  return [...items].sort((a, b) => {
    const an = a.due_date ? 0 : 1;
    const bn = b.due_date ? 0 : 1;
    if (an !== bn) return an - bn;
    if (a.due_date && b.due_date && a.due_date !== b.due_date)
      return a.due_date.localeCompare(b.due_date);
    return b.created_at.localeCompare(a.created_at);
  });
}

/** Städ: aldrig gjorda överst, därefter längst sedan först. */
function sortChores(items: Chore[]): Chore[] {
  return [...items].sort((a, b) => {
    if (!a.last_done_at || !b.last_done_at) return Number(!!a.last_done_at) - Number(!!b.last_done_at);
    return a.last_done_at.localeCompare(b.last_done_at);
  });
}

// ── Refetchers ──────────────────────────────────────────────────────────────
export async function refreshShopping(): Promise<void> {
  const { data, error } = await supabase
    .from('shopping_items')
    .select('*')
    .is('deleted_at', null)
    .is('archived_at', null)
    .order('checked', { ascending: true })
    .order('created_at', { ascending: true });
  if (!error && data) shopping.set(data as ShoppingItem[]);
}

export async function refreshTodos(): Promise<void> {
  const cutoff = new Date(Date.now() - 30 * 86_400_000).toISOString();
  const [open, done] = await Promise.all([
    supabase.from('todos').select('*').eq('done', false).is('deleted_at', null),
    supabase
      .from('todos')
      .select('*')
      .eq('done', true)
      .is('deleted_at', null)
      .gte('done_at', cutoff)
      .order('done_at', { ascending: false })
  ]);
  if (!open.error && open.data) todosOpen.set(sortTodosOpen(open.data as Todo[]));
  if (!done.error && done.data) todosDone.set(done.data as Todo[]);
}

export async function refreshChores(): Promise<void> {
  const { data, error } = await supabase.from('chores').select('*').is('deleted_at', null);
  if (!error && data) chores.set(sortChores(data as Chore[]));
}

export async function refreshActivity(): Promise<void> {
  const { data, error } = await supabase
    .from('activity_log')
    .select('*')
    .order('id', { ascending: false })
    .limit(30);
  if (!error && data) activity.set(data as Activity[]);
}

// Kalenderfönster: 1 vecka bakåt + ~6 veckor framåt (utökas vid scroll).
const DAY = 86_400_000;
let eventFrom = '';
let eventTo = '';
function ensureWindow(): void {
  if (!eventFrom) {
    eventFrom = ymd(new Date(Date.now() - 7 * DAY));
    eventTo = ymd(new Date(Date.now() + 42 * DAY));
  }
}

interface EventRowDb {
  id: string;
  recurrence_id: string;
  title: string;
  location: string | null;
  notes: string | null;
  all_day: boolean;
  start_ts: string | null;
  end_ts: string | null;
  start_date: string | null;
  end_date: string | null;
  created_by: string | null;
  assignee: string | null;
}
const toCalendarEvent = (r: EventRowDb): CalendarEvent => ({
  id: r.id,
  title: r.title,
  allDay: r.all_day,
  start: (r.all_day ? r.start_date : r.start_ts)!,
  end: (r.all_day ? r.end_date : r.end_ts)!,
  location: r.location,
  notes: r.notes,
  createdBy: r.created_by,
  assignee: r.assignee ?? 'both', // omarkerat (t.ex. från Apple Kalender) = gemensamt
  isRecurring: r.recurrence_id !== ''
});

export async function refreshEvents(): Promise<void> {
  ensureWindow();
  const fromUtc = new Date(new Date(eventFrom + 'T00:00:00Z').getTime() - DAY).toISOString();
  const toUtc = new Date(new Date(eventTo + 'T00:00:00Z').getTime() + 2 * DAY).toISOString();
  const { data, error } = await supabase
    .from('events')
    .select('*')
    .is('deleted_at', null)
    .or(
      `and(all_day.eq.false,start_ts.lt.${toUtc},end_ts.gt.${fromUtc}),` +
        `and(all_day.eq.true,start_date.lte.${eventTo},end_date.gt.${eventFrom})`
    );
  if (!error && data) events.set((data as EventRowDb[]).map(toCalendarEvent));
}

export async function extendEvents(): Promise<void> {
  ensureWindow();
  eventTo = ymd(new Date(new Date(eventTo + 'T00:00:00Z').getTime() + 28 * DAY));
  await refreshEvents();
}

export async function refreshAll(): Promise<void> {
  await Promise.allSettled([
    refreshShopping(),
    refreshTodos(),
    refreshChores(),
    refreshFavorites(),
    refreshActivity(),
    refreshEvents()
  ]);
}

// ── Autocomplete (inköp) ────────────────────────────────────────────────────
export async function suggestShopping(q: string): Promise<{ name: string }[]> {
  const { data, error } = await supabase.rpc('suggest_shopping', { q });
  if (error || !data) return [];
  return data as { name: string }[];
}

// ── Inköp ──────────────────────────────────────────────────────────────────
/** Samma regel som DB:ns unika index: aktiv (obockad) vara med samma name_norm. */
function existsActive(name: string): boolean {
  const norm = name.trim().toLowerCase();
  return get(shopping).some((i) => !i.checked && i.name.trim().toLowerCase() === norm);
}

/** Returnerar false om varan redan fanns på listan. */
export async function createShopping(name: string, qty?: string): Promise<boolean> {
  name = name.trim();
  if (!name) return false;
  if (existsActive(name)) {
    showToast('Fanns redan på listan');
    return false;
  }
  const id = uuid();
  const u = get(user);
  const optimistic: ShoppingItem = {
    id,
    name,
    qty: qty?.trim() || null,
    checked: false,
    checked_by: null,
    checked_at: null,
    created_by: u?.id ?? '',
    created_at: nowIso(),
    updated_at: nowIso(),
    version: 1
  };
  shopping.update((l) => sortShopping([...l, optimistic]));

  const res = await sendOp({ op: 'shopping.insert', row: { id, name, qty: qty?.trim() || null } });
  if (!res.sent) return true; // köad offline – optimistisk rad står kvar
  if (res.error) {
    shopping.update((l) => l.filter((i) => i.id !== id));
    if (isDupe(res.error)) showToast('Fanns redan på listan');
    else showToast(errMsg(res.error));
    void refreshShopping();
    return false;
  }
  void refreshShopping();
  return true;
}

export async function setChecked(item: ShoppingItem, checked: boolean): Promise<void> {
  const u = get(user);
  shopping.update((l) =>
    sortShopping(
      l.map((i) =>
        i.id === item.id
          ? {
              ...i,
              checked,
              checked_by: checked ? (u?.id ?? null) : null,
              checked_at: checked ? nowIso() : null
            }
          : i
      )
    )
  );
  const res = await sendOp({
    op: 'shopping.update',
    id: item.id,
    version: item.version,
    patch: { checked }
  });
  if (!res.sent) return;
  if (res.error) {
    showToast(errMsg(res.error));
    void refreshShopping();
    return;
  }
  // 0 rader (versionskonflikt) syns inte här – refetch håller oss ärliga.
  void refreshShopping();
}

export async function editShopping(
  item: ShoppingItem,
  changes: { name?: string; qty?: string | null }
): Promise<void> {
  shopping.update((l) => l.map((i) => (i.id === item.id ? { ...i, ...changes } : i)));
  const res = await sendOp({
    op: 'shopping.update',
    id: item.id,
    version: item.version,
    patch: changes
  });
  if (res.error && isDupe(res.error)) showToast('Finns redan på listan');
  else if (res.error) showToast(errMsg(res.error));
  if (res.sent) void refreshShopping();
}

export async function deleteShopping(item: ShoppingItem): Promise<void> {
  shopping.update((l) => l.filter((i) => i.id !== item.id));
  const res = await sendOp({
    op: 'shopping.update',
    id: item.id,
    version: item.version,
    patch: { deleted_at: nowIso() }
  });
  if (!res.sent) {
    showToast(`Tog bort ${item.name}`, () => void restoreShopping(item.id));
    return;
  }
  if (res.error) {
    shopping.update((l) => sortShopping([...l, item]));
    showToast(errMsg(res.error));
    return;
  }
  showToast(`Tog bort ${item.name}`, () => void restoreShopping(item.id));
  void refreshShopping();
}

export async function restoreShopping(id: string): Promise<void> {
  const { error } = await supabase
    .from('shopping_items')
    .update({ deleted_at: null, deleted_by: null })
    .eq('id', id);
  if (error && isDupe(error)) showToast('Finns redan på listan');
  else if (error) showToast(errMsg(error));
  void refreshShopping();
}

export async function archiveChecked(): Promise<void> {
  const before = get(shopping);
  const checkedItems = before.filter((i) => i.checked);
  if (checkedItems.length === 0) return;
  shopping.set(before.filter((i) => !i.checked));

  const { data, error } = await supabase.rpc('archive_checked');
  if (error) {
    shopping.set(sortShopping(before));
    showToast(errMsg(error));
    return;
  }
  const row = Array.isArray(data) ? data[0] : data;
  const count = Number(row?.count ?? checkedItems.length);
  const ids: string[] = row?.ids ?? checkedItems.map((i) => i.id);
  const label = count === 1 ? '1 vara' : `${count} varor`;
  showToast(`Arkiverade ${label}`, () => void unarchive(ids));
  void refreshActivity();
}

async function unarchive(ids: string[]): Promise<void> {
  await supabase.rpc('unarchive', { p_ids: ids });
  void refreshShopping();
}

// ── Att göra ────────────────────────────────────────────────────────────────
export async function createTodo(input: {
  title: string;
  notes?: string;
  assignee?: string | null;
  start_date?: string | null;
  due_date?: string | null;
}): Promise<void> {
  const title = input.title.trim();
  if (!title) return;
  const id = uuid();
  const u = get(user);
  const optimistic: Todo = {
    id,
    title,
    notes: input.notes?.trim() || null,
    assignee: input.assignee ?? null,
    start_date: input.start_date || null,
    due_date: input.due_date || null,
    done: false,
    done_by: null,
    done_at: null,
    created_by: u?.id ?? '',
    created_at: nowIso(),
    updated_at: nowIso(),
    version: 1
  };
  todosOpen.update((l) => sortTodosOpen([...l, optimistic]));

  const res = await sendOp({
    op: 'todos.insert',
    row: {
      id,
      title,
      notes: input.notes?.trim() || null,
      assignee: input.assignee ?? null,
      start_date: input.start_date || null,
      due_date: input.due_date || null
    }
  });
  if (!res.sent) return;
  if (res.error) {
    todosOpen.update((l) => l.filter((t) => t.id !== id));
    showToast(errMsg(res.error));
    return;
  }
  void refreshTodos();
  void refreshActivity();
}

export async function setTodoDone(todo: Todo, done: boolean): Promise<void> {
  if (done) {
    todosOpen.update((l) => l.filter((t) => t.id !== todo.id));
    todosDone.update((l) => [{ ...todo, done: true, done_at: nowIso() }, ...l]);
  } else {
    todosDone.update((l) => l.filter((t) => t.id !== todo.id));
    todosOpen.update((l) => sortTodosOpen([...l, { ...todo, done: false, done_at: null }]));
  }
  const res = await sendOp({
    op: 'todos.update',
    id: todo.id,
    version: todo.version,
    patch: { done }
  });
  if (!res.sent) {
    if (done) showToast('Klarmarkerad');
    return;
  }
  if (res.error) {
    showToast(errMsg(res.error));
  } else if (done) {
    showToast('Klarmarkerad', () => {
      void supabase
        .from('todos')
        .update({ done: false })
        .eq('id', todo.id)
        .then(() => refreshTodos());
    });
  }
  void refreshTodos();
  void refreshActivity();
}

export async function editTodo(
  todo: Todo,
  changes: {
    title?: string;
    notes?: string | null;
    assignee?: string | null;
    start_date?: string | null;
    due_date?: string | null;
  }
): Promise<void> {
  todosOpen.update((l) => sortTodosOpen(l.map((t) => (t.id === todo.id ? { ...t, ...changes } : t))));
  const res = await sendOp({ op: 'todos.update', id: todo.id, version: todo.version, patch: changes });
  if (res.error) showToast(errMsg(res.error));
  if (res.sent) void refreshTodos();
}

export async function deleteTodo(todo: Todo): Promise<void> {
  todosOpen.update((l) => l.filter((t) => t.id !== todo.id));
  todosDone.update((l) => l.filter((t) => t.id !== todo.id));
  const res = await sendOp({
    op: 'todos.update',
    id: todo.id,
    version: todo.version,
    patch: { deleted_at: nowIso() }
  });
  if (res.error) {
    showToast(errMsg(res.error));
    void refreshTodos();
    return;
  }
  showToast(`Tog bort ${todo.title}`, () => void restoreTodo(todo.id));
  if (res.sent) {
    void refreshTodos();
    void refreshActivity();
  }
}

export async function restoreTodo(id: string): Promise<void> {
  await supabase.from('todos').update({ deleted_at: null, deleted_by: null }).eq('id', id);
  void refreshTodos();
  void refreshActivity();
}

// ── Städ ────────────────────────────────────────────────────────────────────
export async function createChore(input: { title: string; assignee?: string | null }): Promise<void> {
  const title = input.title.trim();
  if (!title) return;
  const id = uuid();
  const u = get(user);
  const optimistic: Chore = {
    id,
    title,
    assignee: input.assignee ?? null,
    last_done_at: null,
    last_done_by: null,
    created_by: u?.id ?? '',
    created_at: nowIso(),
    updated_at: nowIso(),
    version: 1
  };
  chores.update((l) => sortChores([...l, optimistic]));

  const res = await sendOp({
    op: 'chores.insert',
    row: { id, title, assignee: input.assignee ?? null }
  });
  if (!res.sent) return;
  if (res.error) {
    chores.update((l) => l.filter((c) => c.id !== id));
    showToast(errMsg(res.error));
    return;
  }
  void refreshChores();
  void refreshActivity();
}

/** "Gjort nu": servern sätter last_done_by/at; ångra återställer förra värdena. */
export async function tickChore(chore: Chore): Promise<void> {
  const u = get(user);
  const done = { ...chore, last_done_at: nowIso(), last_done_by: u?.id ?? null };
  chores.update((l) => sortChores(l.map((c) => (c.id === chore.id ? done : c))));

  const res = await sendOp({
    op: 'chores.update',
    id: chore.id,
    version: chore.version,
    patch: { last_done_at: done.last_done_at }
  });
  if (!res.sent) {
    showToast(`Gjort: ${chore.title}`);
    return;
  }
  if (res.error) {
    showToast(errMsg(res.error));
  } else {
    showToast(`Gjort: ${chore.title}`, () => {
      void supabase
        .from('chores')
        .update({ last_done_at: chore.last_done_at, last_done_by: chore.last_done_by })
        .eq('id', chore.id)
        .then(() => refreshChores());
    });
  }
  void refreshChores();
  void refreshActivity();
}

export async function deleteChore(chore: Chore): Promise<void> {
  chores.update((l) => l.filter((c) => c.id !== chore.id));
  const res = await sendOp({
    op: 'chores.update',
    id: chore.id,
    version: chore.version,
    patch: { deleted_at: nowIso() }
  });
  if (res.error) {
    showToast(errMsg(res.error));
    void refreshChores();
    return;
  }
  showToast(`Tog bort ${chore.title}`, () => void restoreChore(chore.id));
  if (res.sent) {
    void refreshChores();
    void refreshActivity();
  }
}

export async function restoreChore(id: string): Promise<void> {
  await supabase.from('chores').update({ deleted_at: null, deleted_by: null }).eq('id', id);
  void refreshChores();
  void refreshActivity();
}

// ── Favoritmiddagar ─────────────────────────────────────────────────────────
export async function refreshFavorites(): Promise<void> {
  const { data, error } = await supabase
    .from('favorites')
    .select('*')
    .is('deleted_at', null)
    .order('name');
  if (!error && data) favorites.set(data as Favorite[]);
}

/** Skapar favoriten och returnerar dess id (null vid fel). */
export async function createFavorite(input: {
  name: string;
  items: string[];
  image_url?: string | null;
  source_url?: string | null;
}): Promise<string | null> {
  const id = uuid();
  const u = get(user);
  const { error } = await supabase.from('favorites').insert({
    id,
    name: input.name.trim(),
    items: input.items,
    image_url: input.image_url ?? null,
    source_url: input.source_url ?? null,
    created_by: u?.id ?? ''
  });
  if (error) {
    showToast(errMsg(error));
    return null;
  }
  await refreshFavorites();
  return id;
}

export async function deleteFavorite(fav: Favorite): Promise<void> {
  favorites.update((l) => l.filter((f) => f.id !== fav.id));
  const { error } = await supabase.from('favorites').update({ deleted_at: nowIso() }).eq('id', fav.id);
  if (error) {
    showToast(errMsg(error));
    void refreshFavorites();
    return;
  }
  showToast(`Tog bort ${fav.name}`, () => void restoreFavorite(fav.id));
}

export async function restoreFavorite(id: string): Promise<void> {
  await supabase.from('favorites').update({ deleted_at: null }).eq('id', id);
  void refreshFavorites();
}

/** Hämta namn/bild/ingredienser från en receptsida (sparar inte). */
export async function importRecipe(url: string): Promise<ImportedRecipe | null> {
  const { data, error } = await supabase.functions.invoke('recipe-import', { body: { url } });
  if (!error) return (data?.recipe as ImportedRecipe) ?? null;
  let message = 'Kunde inte hämta receptet.';
  try {
    const ctx = (error as { context?: Response }).context;
    if (ctx) message = (await ctx.json())?.error?.message ?? message;
  } catch {
    /* behåll standardtexten */
  }
  showToast(message);
  return null;
}

/** Ingrediensrader → inköpslistan (mängden blir antal-fältet). Returnerar antal tillagda. */
export async function addIngredientsToList(lines: string[]): Promise<number> {
  let added = 0;
  for (const line of lines) {
    const { name, qty } = splitIngredient(line);
    if (await createShopping(name, qty ?? undefined)) added++;
  }
  return added;
}

// ── Kalender (aldrig via outbox – kräver nät) ───────────────────────────────
export interface EventInput {
  title: string;
  allDay: boolean;
  start: string;
  end: string;
  location?: string | null;
  notes?: string | null;
  assignee?: string | null; // users.id | 'both'
}

interface EdgeError {
  code?: string;
  message?: string;
  current?: EventRowDb;
}

async function invokeEventWrite(body: Record<string, unknown>): Promise<
  { ok: true; event?: CalendarEvent } | { ok: false; err: EdgeError }
> {
  const { data, error } = await supabase.functions.invoke('event-write', { body });
  if (!error) {
    return { ok: true, event: data?.event ? toCalendarEvent(data.event) : undefined };
  }
  // FunctionsHttpError bär svaret i .context
  try {
    const ctx = (error as { context?: Response }).context;
    if (ctx) {
      const parsed = (await ctx.json()) as { error?: EdgeError };
      return { ok: false, err: parsed.error ?? {} };
    }
  } catch {
    /* ignore */
  }
  return { ok: false, err: { message: 'Kunde inte nå kalendern.' } };
}

export async function createEventAction(input: EventInput): Promise<boolean> {
  const res = await invokeEventWrite({ action: 'create', ...input });
  if (res.ok) {
    void refreshEvents();
    void refreshActivity();
    return true;
  }
  showToast(res.err.message ?? 'Kunde inte spara i kalendern.');
  return false;
}

export async function updateEventAction(
  id: string,
  changes: Partial<EventInput>
): Promise<{ ok: boolean; conflict?: CalendarEvent }> {
  const res = await invokeEventWrite({ action: 'update', id, ...changes });
  if (res.ok) {
    void refreshEvents();
    void refreshActivity();
    return { ok: true };
  }
  if (res.err.code === 'caldav_conflict' && res.err.current) {
    const current = toCalendarEvent(res.err.current);
    events.update((l) => l.map((e) => (e.id === current.id ? current : e)));
    return { ok: false, conflict: current };
  }
  showToast(res.err.message ?? 'Kunde inte spara i kalendern.');
  return { ok: false };
}

export async function deleteEventAction(ev: CalendarEvent): Promise<void> {
  const before = get(events);
  events.update((l) => l.filter((e) => e.id !== ev.id));
  const res = await invokeEventWrite({ action: 'delete', id: ev.id });
  if (res.ok) {
    showToast(`Tog bort ${ev.title}`, () => void restoreEventAction(ev.id));
    void refreshActivity();
  } else if (res.err.code === 'caldav_conflict') {
    showToast('Händelsen ändrades av någon annan');
    void refreshEvents();
  } else {
    events.set(before);
    showToast(res.err.message ?? 'Kunde inte radera i kalendern.');
  }
}

export async function restoreEventAction(id: string): Promise<void> {
  const res = await invokeEventWrite({ action: 'restore', id });
  if (!res.ok) showToast(res.err.message ?? 'Kunde inte återställa.');
  void refreshEvents();
  void refreshActivity();
}
