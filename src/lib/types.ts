/** Delade typer mellan server och klient. */

export interface User {
  id: string;
  name: string;
  color: string;
}

export interface NotificationPrefs {
  enabled: boolean;
  quiet_from: string;
  quiet_to: string;
  digest_minutes: number;
}

export interface SyncStatus {
  last_synced_at: string | null;
  failing_since: string | null;
  last_error?: string | null;
}

export interface MeResponse {
  user: User;
  partner: User | null;
  prefs: NotificationPrefs;
  syncStatus: SyncStatus;
  vapidPublicKey: string;
}

export interface ShoppingItem {
  id: string;
  name: string;
  qty: string | null;
  checked: boolean;
  checked_by: string | null;
  checked_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface Todo {
  id: string;
  title: string;
  notes: string | null;
  assignee: string | null; // users.id | 'both' | null
  start_date: string | null; // sätter en period start_date..due_date ("gör inom")
  due_date: string | null;
  done: boolean;
  done_by: string | null;
  done_at: string | null;
  created_by: string;
  created_at: string;
  updated_at: string;
  version: number;
}

export interface CalendarEvent {
  id: string;
  title: string;
  allDay: boolean;
  start: string; // ISO-ts (tidsatt) eller YYYY-MM-DD (heldag)
  end: string;
  location: string | null;
  notes?: string | null;
  createdBy: string | null;
  isRecurring: boolean;
}

export interface Activity {
  id: number;
  type: string;
  actor: string;
  entity_type: 'shopping' | 'todo' | 'event';
  entity_id: string;
  payload: Record<string, unknown> | null;
  created_at: string;
}

export type ApiErrorCode =
  | 'unauthorized'
  | 'forbidden'
  | 'not_found'
  | 'validation'
  | 'version_conflict'
  | 'duplicate'
  | 'caldav_conflict'
  | 'caldav_unavailable';

export interface ApiError {
  error: { code: ApiErrorCode; message: string; [k: string]: unknown };
}
