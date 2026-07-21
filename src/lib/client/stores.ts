/** Delade Svelte-stores (spec §3: user, shopping, todos, events, activity, online). */
import { writable } from 'svelte/store';
import type { User, MeResponse, ShoppingItem, Todo, Activity, CalendarEvent } from '$lib/types';

export const user = writable<User | null>(null);
export const me = writable<MeResponse | null>(null);
export const online = writable<boolean>(true);

export const shopping = writable<ShoppingItem[]>([]);
export const todosOpen = writable<Todo[]>([]);
export const todosDone = writable<Todo[]>([]);
export const activity = writable<Activity[]>([]);
export const events = writable<CalendarEvent[]>([]);

/** Global skapa-sheet (FAB) – öppnas oavsett aktiv vy (spec §12.1). */
export const createKind = writable<'event' | 'shopping' | 'todo' | null>(null);

/** Ångra-toast (spec §12.1). */
export interface ToastState {
  id: number;
  message: string;
  undo?: () => void;
}
export const toast = writable<ToastState | null>(null);

let toastSeq = 0;
let toastTimer: ReturnType<typeof setTimeout> | undefined;

export function showToast(message: string, undo?: () => void): void {
  const id = ++toastSeq;
  toast.set({ id, message, undo });
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => {
    toast.update((t) => (t && t.id === id ? null : t));
  }, 6000);
}

export function dismissToast(): void {
  clearTimeout(toastTimer);
  toast.set(null);
}

export function uuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  return 'id-' + Math.random().toString(36).slice(2) + Date.now().toString(36);
}

/** Startas i +layout.svelte (endast klient). */
export function trackOnline(): () => void {
  if (typeof navigator === 'undefined') return () => {};
  online.set(navigator.onLine);
  const on = () => online.set(true);
  const off = () => online.set(false);
  window.addEventListener('online', on);
  window.addEventListener('offline', off);
  return () => {
    window.removeEventListener('online', on);
    window.removeEventListener('offline', off);
  };
}
