/**
 * SSE-klientregister + broadcast (spec §10).
 * broadcast(entity, exceptConnId) skickar `event: changed` till alla anslutna
 * UTOM avsändarens egen anslutning (den uppdaterar redan optimistiskt).
 */
type Entity = 'shopping' | 'todos' | 'todo' | 'events' | 'activity';

interface Client {
  id: string;
  send: (chunk: string) => void;
}

// Överlev HMR i dev.
const g = globalThis as unknown as { __planeraren_sse?: Map<string, Client> };
const clients = g.__planeraren_sse ?? (g.__planeraren_sse = new Map<string, Client>());

export function addClient(id: string, send: (chunk: string) => void): void {
  clients.set(id, { id, send });
}

export function removeClient(id: string): void {
  clients.delete(id);
}

export function broadcast(entity: Entity, exceptConnId?: string): void {
  const msg = `event: changed\ndata: ${JSON.stringify({ entity })}\n\n`;
  for (const c of clients.values()) {
    if (c.id === exceptConnId) continue;
    try {
      c.send(msg);
    } catch {
      clients.delete(c.id);
    }
  }
}

export function clientCount(): number {
  return clients.size;
}
