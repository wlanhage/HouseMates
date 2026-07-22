/**
 * Realtid via Supabase Realtime (ersätter SSE). Prenumererar på postgres-
 * ändringar och refetch:ar berörd lista. Vid återanslutning: outbox-replay +
 * hämta allt (samma kontrakt som gamla sse.ts).
 */
import { supabase } from './supabase';
import {
  refreshShopping,
  refreshTodos,
  refreshActivity,
  refreshEvents,
  refreshAll
} from './data';
import { replayOutbox } from './outbox';
import { loadMe } from './auth';

export function startRealtime(): () => void {
  let everSubscribed = false;

  const channel = supabase
    .channel('planeraren-db')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'shopping_items' }, () => {
      void refreshShopping();
      void refreshActivity();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'todos' }, () => {
      void refreshTodos();
      void refreshActivity();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'events' }, () => {
      void refreshEvents();
    })
    .on('postgres_changes', { event: '*', schema: 'public', table: 'sync_state' }, () => {
      void loadMe();
    })
    .subscribe((status) => {
      if (status === 'SUBSCRIBED') {
        if (everSubscribed) {
          // Återanslutning → spela upp kön + hämta färskt
          void replayOutbox().then(() => refreshAll());
        }
        everSubscribed = true;
      }
    });

  return () => {
    void supabase.removeChannel(channel);
  };
}
