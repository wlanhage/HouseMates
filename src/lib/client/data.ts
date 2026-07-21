/**
 * Klientens "actions" – optimistiska mutationer mot storarna, via outbox
 * (offline-kö) och med återställning vid 4xx + ångra-toast (spec §12).
 *
 * Online: mutationen skickas direkt. Offline / nätverksfel: den köas och
 * spelas upp vid reconnect (idempotens via klient-uuid → inga dubbletter).
 */
import { get } from 'svelte/store';
import { apiGet, apiPost, apiPatch, apiDelete, ApiError } from './api';
import { sendMutation } from './outbox';
import { shopping, todosOpen, todosDone, activity, events, user, showToast, uuid } from './stores';
import { ymd } from './dates';
import type { ShoppingItem, Todo, Activity, CalendarEvent } from '$lib/types';

const nowIso = () => new Date().toISOString();
const errMsg = (e: unknown) => (e instanceof ApiError ? e.message : 'Något gick fel.');

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

// ── Refetchers (bästa förmåga; offline lämnas spegeldatan orörd) ────────────
export async function refreshShopping(): Promise<void> {
  try {
    shopping.set(await apiGet<ShoppingItem[]>('/api/shopping'));
  } catch {
    /* offline → behåll spegeln */
  }
}
export async function refreshTodos(): Promise<void> {
  try {
    const [open, done] = await Promise.all([
      apiGet<Todo[]>('/api/todos?filter=open'),
      apiGet<Todo[]>('/api/todos?filter=done')
    ]);
    todosOpen.set(open);
    todosDone.set(done);
  } catch {
    /* offline */
  }
}
export async function refreshActivity(): Promise<void> {
  try {
    activity.set(await apiGet<Activity[]>('/api/activity?limit=30'));
  } catch {
    /* offline */
  }
}

// Kalenderfönster: rullande 1 vecka bakåt + ~5 veckor framåt (spec §12.2).
const DAY = 86_400_000;
let eventFrom = '';
let eventTo = '';
function ensureWindow(): void {
  if (!eventFrom) {
    eventFrom = ymd(new Date(Date.now() - 7 * DAY));
    eventTo = ymd(new Date(Date.now() + 42 * DAY));
  }
}
export async function refreshEvents(): Promise<void> {
  ensureWindow();
  try {
    events.set(await apiGet<CalendarEvent[]>(`/api/events?from=${eventFrom}&to=${eventTo}`));
  } catch {
    /* offline → behåll spegeln */
  }
}
/** Utöka fönstret framåt (infinite scroll). */
export async function extendEvents(): Promise<void> {
  ensureWindow();
  eventTo = ymd(new Date(new Date(eventTo + 'T00:00:00Z').getTime() + 28 * DAY));
  await refreshEvents();
}

export async function refreshAll(): Promise<void> {
  await Promise.allSettled([refreshShopping(), refreshTodos(), refreshActivity(), refreshEvents()]);
}

let activityTimer: ReturnType<typeof setTimeout> | undefined;
function bumpActivity(): void {
  clearTimeout(activityTimer);
  activityTimer = setTimeout(() => void refreshActivity(), 150);
}

// ── Inköp ──────────────────────────────────────────────────────────────────
export async function createShopping(name: string, qty?: string): Promise<void> {
  name = name.trim();
  if (!name) return;
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
  try {
    const res = await sendMutation<{ item: ShoppingItem; merged: boolean }>({
      method: 'POST',
      path: '/api/shopping',
      body: { id, name, qty: qty?.trim() || undefined },
      entity: 'shopping'
    });
    if (res.data) {
      shopping.update((l) => {
        const without = l.filter((i) => i.id !== id && i.id !== res.data!.item.id);
        return sortShopping([...without, res.data!.item]);
      });
      if (res.data.merged) showToast('Fanns redan på listan');
      bumpActivity();
    }
    // queued → optimistic (id = klient-uuid) står kvar tills replay
  } catch (e) {
    shopping.update((l) => l.filter((i) => i.id !== id));
    showToast(errMsg(e));
  }
}

export async function setChecked(item: ShoppingItem, checked: boolean): Promise<void> {
  const u = get(user);
  const optimistic: ShoppingItem = {
    ...item,
    checked,
    checked_by: checked ? (u?.id ?? null) : null,
    checked_at: checked ? nowIso() : null
  };
  shopping.update((l) => sortShopping(l.map((i) => (i.id === item.id ? optimistic : i))));
  try {
    const res = await sendMutation<ShoppingItem>({
      method: 'PATCH',
      path: `/api/shopping/${item.id}`,
      body: { version: item.version, checked },
      entity: 'shopping'
    });
    if (res.data) {
      shopping.update((l) => sortShopping(l.map((i) => (i.id === item.id ? res.data! : i))));
      bumpActivity();
    }
  } catch (e) {
    if (e instanceof ApiError && e.code === 'version_conflict' && e.extra.current) {
      shopping.update((l) =>
        sortShopping(l.map((i) => (i.id === item.id ? (e.extra.current as ShoppingItem) : i)))
      );
      showToast('Uppdaterades av någon annan');
    } else {
      shopping.update((l) => sortShopping(l.map((i) => (i.id === item.id ? item : i))));
      showToast(errMsg(e));
    }
  }
}

export async function editShopping(
  item: ShoppingItem,
  changes: { name?: string; qty?: string | null }
): Promise<void> {
  shopping.update((l) => l.map((i) => (i.id === item.id ? { ...item, ...changes } : i)));
  try {
    const res = await sendMutation<ShoppingItem>({
      method: 'PATCH',
      path: `/api/shopping/${item.id}`,
      body: { version: item.version, ...changes },
      entity: 'shopping'
    });
    if (res.data) shopping.update((l) => sortShopping(l.map((i) => (i.id === item.id ? res.data! : i))));
  } catch (e) {
    if (e instanceof ApiError && e.code === 'version_conflict' && e.extra.current) {
      shopping.update((l) => l.map((i) => (i.id === item.id ? (e.extra.current as ShoppingItem) : i)));
      showToast('Uppdaterades av någon annan');
    } else {
      shopping.update((l) => l.map((i) => (i.id === item.id ? item : i)));
      showToast(errMsg(e));
    }
  }
}

export async function deleteShopping(item: ShoppingItem): Promise<void> {
  shopping.update((l) => l.filter((i) => i.id !== item.id));
  try {
    await sendMutation({ method: 'DELETE', path: `/api/shopping/${item.id}`, entity: 'shopping' });
    showToast(`Tog bort ${item.name}`, () => void restoreShopping(item.id));
    bumpActivity();
  } catch (e) {
    shopping.update((l) => sortShopping([...l, item]));
    showToast(errMsg(e));
  }
}

export async function restoreShopping(id: string): Promise<void> {
  try {
    const res = await sendMutation<ShoppingItem>({
      method: 'POST',
      path: `/api/shopping/${id}/restore`,
      entity: 'shopping'
    });
    if (res.data) shopping.update((l) => sortShopping([...l.filter((i) => i.id !== res.data!.id), res.data!]));
    bumpActivity();
  } catch (e) {
    if (e instanceof ApiError && e.code === 'duplicate') showToast('Finns redan på listan');
    else showToast(errMsg(e));
    void refreshShopping();
  }
}

export async function archiveChecked(): Promise<void> {
  const before = get(shopping);
  const checkedItems = before.filter((i) => i.checked);
  if (checkedItems.length === 0) return;
  shopping.set(before.filter((i) => !i.checked));
  try {
    const res = await sendMutation<{ count: number; ids: string[] }>({
      method: 'POST',
      path: '/api/shopping/archive-checked',
      entity: 'shopping'
    });
    const ids = res.data?.ids ?? checkedItems.map((i) => i.id);
    const count = res.data?.count ?? checkedItems.length;
    const label = count === 1 ? '1 vara' : `${count} varor`;
    showToast(`Arkiverade ${label}`, () => void unarchive(ids));
    bumpActivity();
  } catch (e) {
    shopping.set(sortShopping(before));
    showToast(errMsg(e));
  }
}

async function unarchive(ids: string[]): Promise<void> {
  try {
    await sendMutation({ method: 'POST', path: '/api/shopping/unarchive', body: { ids }, entity: 'shopping' });
  } finally {
    void refreshShopping();
  }
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
  try {
    const res = await sendMutation<Todo>({
      method: 'POST',
      path: '/api/todos',
      body: {
        id,
        title,
        notes: input.notes?.trim() || undefined,
        assignee: input.assignee ?? undefined,
        start_date: input.start_date || undefined,
        due_date: input.due_date || undefined
      },
      entity: 'todos'
    });
    if (res.data) {
      todosOpen.update((l) => sortTodosOpen(l.map((t) => (t.id === id ? res.data! : t))));
      bumpActivity();
    }
  } catch (e) {
    todosOpen.update((l) => l.filter((t) => t.id !== id));
    showToast(errMsg(e));
  }
}

export async function setTodoDone(todo: Todo, done: boolean): Promise<void> {
  if (done) {
    todosOpen.update((l) => l.filter((t) => t.id !== todo.id));
    todosDone.update((l) => [{ ...todo, done: true, done_at: nowIso() }, ...l]);
  } else {
    todosDone.update((l) => l.filter((t) => t.id !== todo.id));
    todosOpen.update((l) => sortTodosOpen([...l, { ...todo, done: false, done_at: null }]));
  }
  try {
    const res = await sendMutation<Todo>({
      method: 'PATCH',
      path: `/api/todos/${todo.id}`,
      body: { version: todo.version, done },
      entity: 'todos'
    });
    if (res.data) {
      todosOpen.update((l) => l.map((t) => (t.id === todo.id ? res.data! : t)));
      todosDone.update((l) => l.map((t) => (t.id === todo.id ? res.data! : t)));
      bumpActivity();
    }
    if (done) showToast('Klarmarkerad', () => void setTodoDone({ ...todo, version: todo.version + 1 }, false));
  } catch (e) {
    if (e instanceof ApiError && e.code === 'version_conflict') showToast('Uppdaterades av någon annan');
    else showToast(errMsg(e));
    void refreshTodos();
  }
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
  todosOpen.update((l) => sortTodosOpen(l.map((t) => (t.id === todo.id ? { ...todo, ...changes } : t))));
  try {
    const res = await sendMutation<Todo>({
      method: 'PATCH',
      path: `/api/todos/${todo.id}`,
      body: { version: todo.version, ...changes },
      entity: 'todos'
    });
    if (res.data) todosOpen.update((l) => sortTodosOpen(l.map((t) => (t.id === todo.id ? res.data! : t))));
  } catch (e) {
    if (e instanceof ApiError && e.code === 'version_conflict') showToast('Uppdaterades av någon annan');
    else showToast(errMsg(e));
    void refreshTodos();
  }
}

export async function deleteTodo(todo: Todo): Promise<void> {
  todosOpen.update((l) => l.filter((t) => t.id !== todo.id));
  todosDone.update((l) => l.filter((t) => t.id !== todo.id));
  try {
    await sendMutation({ method: 'DELETE', path: `/api/todos/${todo.id}`, entity: 'todos' });
    showToast(`Tog bort ${todo.title}`, () => void restoreTodo(todo.id));
    bumpActivity();
  } catch (e) {
    void refreshTodos();
    showToast(errMsg(e));
  }
}

export async function restoreTodo(id: string): Promise<void> {
  try {
    await sendMutation({ method: 'POST', path: `/api/todos/${id}/restore`, entity: 'todos' });
    bumpActivity();
  } catch (e) {
    showToast(errMsg(e));
  } finally {
    void refreshTodos();
  }
}

// ── Kalender (aldrig via outbox – kräver nät, spec §7.5) ─────────────────────
export interface EventInput {
  title: string;
  allDay: boolean;
  start: string;
  end: string;
  location?: string | null;
  notes?: string | null;
}

export async function createEventAction(input: EventInput): Promise<boolean> {
  try {
    const ev = await apiPost<CalendarEvent>('/api/events', input);
    events.update((l) => [...l.filter((e) => e.id !== ev.id), ev]);
    bumpActivity();
    return true;
  } catch (e) {
    showToast(errMsg(e));
    return false;
  }
}

/** Returnerar { ok } eller { conflict } (färsk kopia) vid caldav_conflict. */
export async function updateEventAction(
  id: string,
  changes: Partial<EventInput>
): Promise<{ ok: boolean; conflict?: CalendarEvent }> {
  try {
    const ev = await apiPatch<CalendarEvent>(`/api/events/${id}`, changes);
    events.update((l) => l.map((e) => (e.id === ev.id ? ev : e)));
    bumpActivity();
    return { ok: true };
  } catch (e) {
    if (e instanceof ApiError && e.code === 'caldav_conflict' && e.extra.current) {
      const current = e.extra.current as CalendarEvent;
      events.update((l) => l.map((e2) => (e2.id === current.id ? current : e2)));
      return { ok: false, conflict: current };
    }
    showToast(errMsg(e));
    return { ok: false };
  }
}

export async function deleteEventAction(ev: CalendarEvent): Promise<void> {
  const before = get(events);
  events.update((l) => l.filter((e) => e.id !== ev.id));
  try {
    await apiDelete(`/api/events/${ev.id}`);
    showToast(`Tog bort ${ev.title}`, () => void restoreEventAction(ev.id));
    bumpActivity();
  } catch (e) {
    if (e instanceof ApiError && e.code === 'caldav_conflict') {
      showToast('Händelsen ändrades av någon annan');
      void refreshEvents();
    } else {
      events.set(before);
      showToast(errMsg(e));
    }
  }
}

export async function restoreEventAction(id: string): Promise<void> {
  try {
    await apiPost(`/api/events/${id}/restore`);
    bumpActivity();
  } catch (e) {
    showToast(errMsg(e));
  } finally {
    void refreshEvents();
  }
}
