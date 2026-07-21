/**
 * EventSource med exponentiell backoff-reconnect (spec §10).
 * Vid `changed` → refetch berörd lista. Vid reconnect → refetch allt
 * (+ outbox-replay i M3).
 */
import { connId } from './conn';
import { refreshShopping, refreshTodos, refreshActivity, refreshEvents, refreshAll } from './data';
import { replayOutbox } from './outbox';

let es: EventSource | null = null;
let backoff = 1000;
let closed = false;
let everConnected = false;

function handleChanged(entity: string): void {
  if (entity === 'shopping') void refreshShopping();
  else if (entity === 'todos' || entity === 'todo') void refreshTodos();
  else if (entity === 'events') void refreshEvents();
  // App-mutationer skapar en activity-rad; synkade kalenderändringar gör inte
  // det (spec §8) men en extra refetch är ofarlig (samma data).
  void refreshActivity();
}

function connect(): void {
  es = new EventSource(`/api/stream?id=${encodeURIComponent(connId)}`);

  es.addEventListener('open', () => {
    backoff = 1000;
    // reconnect → spela upp kön och hämta allt igen
    if (everConnected) void replayOutbox().then(() => refreshAll());
    everConnected = true;
  });

  es.addEventListener('changed', (ev) => {
    try {
      const data = JSON.parse((ev as MessageEvent).data) as { entity: string };
      handleChanged(data.entity);
    } catch {
      void refreshAll();
    }
  });

  es.addEventListener('error', () => {
    es?.close();
    es = null;
    if (closed) return;
    setTimeout(connect, backoff);
    backoff = Math.min(backoff * 2, 30_000);
  });
}

/** Starta strömmen. Returnerar en stopp-funktion. */
export function startSSE(): () => void {
  if (typeof window === 'undefined') return () => {};
  closed = false;
  everConnected = false;
  connect();
  return () => {
    closed = true;
    es?.close();
    es = null;
  };
}
