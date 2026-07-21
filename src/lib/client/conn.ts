/** Unikt id per öppen flik – används för SSE (?id=) och X-Conn-Id-headern
 *  så att broadcast hoppar över avsändarens egen anslutning (spec §10). */
function makeId(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID();
  return 'c-' + Math.random().toString(36).slice(2);
}

export const connId = makeId();
