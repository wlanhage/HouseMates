/** Speglar src/lib/server/digest.ts (testad i vitest). Håll filerna lika. */
export interface DigestActivity {
  type: string; // t.ex. 'shopping.checked'
  entity_id: string;
  payload: Record<string, unknown> | null;
}

export interface Digest {
  title: string;
  body: string;
  url: string; // relativ appens bas, t.ex. 'inkop'
}

type Kind = 'shopping' | 'todo' | 'chore' | 'event';

interface Entity {
  kind: Kind;
  label: string;
  when: string | null;
  added: boolean;
  done: boolean;
  removed: boolean;
  updated: boolean;
}

type GroupKey =
  | 'bought'
  | 'choresDone'
  | 'todosDone'
  | 'eventsCreated'
  | 'added'
  | 'todosCreated'
  | 'choresCreated'
  | 'eventsUpdated'
  | 'removed'
  | 'todosDeleted'
  | 'eventsDeleted';

interface GroupSpec {
  title: (actor: string, n: number, first: string) => string;
  line: string; // radetikett när flera grupper visas
  url: string;
}

const pl = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`;

// Prioritetsordning = ordning här: den första gruppen som finns styr rubrik och länk.
const GROUPS: [GroupKey, GroupSpec][] = [
  ['bought', { title: (a, n, x) => (n === 1 ? `${a} handlade ${x}` : `${a} handlade ${n} varor`), line: 'Handlade', url: 'inkop' }],
  ['choresDone', { title: (a) => `${a} städade`, line: 'Städade', url: 'todo' }],
  ['todosDone', { title: (a, n, x) => (n === 1 ? `${a} klarade av ${x}` : `${a} klarade av ${n} uppgifter`), line: 'Klarade av', url: 'todo' }],
  ['eventsCreated', { title: (a, n, x) => (n === 1 ? `${a} la in ${x} i kalendern` : `${a} la in ${pl(n, 'händelse', 'händelser')} i kalendern`), line: 'Kalender', url: 'kalender' }],
  ['added', { title: (a, n, x) => (n === 1 ? `${a} la till ${x} på listan` : `${a} la till ${n} varor på listan`), line: 'La till på listan', url: 'inkop' }],
  ['todosCreated', { title: (a, n, x) => (n === 1 ? `${a} la till uppgiften ${x}` : `${a} la till ${n} uppgifter`), line: 'Nya uppgifter', url: 'todo' }],
  ['choresCreated', { title: (a, n, x) => (n === 1 ? `${a} la till städsysslan ${x}` : `${a} la till ${n} städsysslor`), line: 'Nya städsysslor', url: 'todo' }],
  ['eventsUpdated', { title: (a, n, x) => (n === 1 ? `${a} ändrade ${x} i kalendern` : `${a} ändrade ${pl(n, 'händelse', 'händelser')} i kalendern`), line: 'Ändrade i kalendern', url: 'kalender' }],
  ['removed', { title: (a, n, x) => (n === 1 ? `${a} tog bort ${x} från listan` : `${a} tog bort ${n} varor från listan`), line: 'Tog bort från listan', url: 'inkop' }],
  ['todosDeleted', { title: (a, n, x) => (n === 1 ? `${a} tog bort uppgiften ${x}` : `${a} tog bort ${n} uppgifter`), line: 'Tog bort uppgifter', url: 'todo' }],
  ['eventsDeleted', { title: (a, n, x) => (n === 1 ? `${a} tog bort ${x} ur kalendern` : `${a} tog bort ${pl(n, 'händelse', 'händelser')} ur kalendern`), line: 'Tog bort ur kalendern', url: 'kalender' }]
];

/** "Mjölk och Bröd" / "Mjölk, Bröd, Kaffe, Smör, Ägg + 2 till" */
export function listNames(names: string[], max = 5): string {
  if (names.length === 2) return `${names[0]} och ${names[1]}`;
  const shown = names.slice(0, max);
  const extra = names.length - shown.length;
  return shown.join(', ') + (extra > 0 ? ` + ${extra} till` : '');
}

/** "ons 16 sep. 12:00" / "ons 16 sep." (heldag) i svensk tid. */
export function whenLabel(start: string | null, tz = 'Europe/Stockholm'): string {
  if (!start) return '';
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.test(start);
  const d = dateOnly ? new Date(`${start}T12:00:00Z`) : new Date(start);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: dateOnly ? 'UTC' : tz,
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    ...(dateOnly ? {} : { hour: '2-digit', minute: '2-digit' })
  }).format(d);
}

/** Netta händelserna per sak till ett slutläge. */
function collapse(acts: DigestActivity[]): Entity[] {
  const map = new Map<string, Entity>();
  for (const a of acts) {
    const [kind, verb] = a.type.split('.') as [Kind, string];
    if (verb === 'archived') continue;
    const key = `${kind}:${a.entity_id}`;
    let e = map.get(key);
    if (!e) {
      e = { kind, label: '', when: null, added: false, done: false, removed: false, updated: false };
      map.set(key, e);
    }
    const label = (a.payload?.name ?? a.payload?.title) as string | undefined;
    if (label) e.label = label;
    if (typeof a.payload?.start === 'string') e.when = a.payload.start;
    switch (verb) {
      case 'added':
      case 'created':
        e.added = true;
        e.removed = false;
        break;
      case 'checked':
      case 'done':
        e.done = true;
        break;
      case 'unchecked':
      case 'undone':
        e.done = false;
        break;
      case 'deleted':
        e.removed = true;
        e.done = false;
        break;
      case 'restored':
        e.removed = false;
        break;
      case 'updated':
        e.updated = true;
        break;
    }
  }
  return [...map.values()];
}

function groupOf(e: Entity): GroupKey | null {
  if (e.removed && e.added) return null; // skapad och borttagen i samma fönster
  if (e.removed) return ({ shopping: 'removed', todo: 'todosDeleted', event: 'eventsDeleted', chore: null } as const)[e.kind];
  if (e.done) return ({ shopping: 'bought', todo: 'todosDone', chore: 'choresDone', event: null } as const)[e.kind];
  if (e.added) return ({ shopping: 'added', todo: 'todosCreated', chore: 'choresCreated', event: 'eventsCreated' } as const)[e.kind];
  if (e.updated && e.kind === 'event') return 'eventsUpdated';
  return null;
}

export function buildDigest(actor: string, acts: DigestActivity[]): Digest | null {
  const byGroup = new Map<GroupKey, Entity[]>();
  for (const e of collapse(acts)) {
    const g = groupOf(e);
    if (!g) continue;
    byGroup.set(g, [...(byGroup.get(g) ?? []), e]);
  }
  const present = GROUPS.filter(([key]) => byGroup.has(key));
  if (present.length === 0) return null;

  const nameOf = (e: Entity) => e.label || (e.kind === 'event' ? 'händelse' : 'något');
  const detail = (key: GroupKey, es: Entity[]) =>
    key === 'eventsCreated'
      ? listNames(es.map((e) => (e.when ? `${nameOf(e)} ${whenLabel(e.when)}` : nameOf(e))), 4)
      : listNames(es.map(nameOf));

  const [firstKey, firstSpec] = present[0];
  const first = byGroup.get(firstKey)!;

  if (present.length === 1) {
    const n = first.length;
    const title = firstSpec.title(actor, n, nameOf(first[0]));
    // Namnet står redan i rubriken när det är en enda sak (utom städ, vars rubrik är generell)
    const body = n === 1 && firstKey !== 'choresDone' ? (firstKey === 'eventsCreated' ? whenLabel(first[0].when) : '') : detail(firstKey, first);
    return { title, body, url: firstSpec.url };
  }

  const lines = present.map(([key, spec]) => `${spec.line}: ${detail(key, byGroup.get(key)!)}`);
  return { title: `Nytt från ${actor}`, body: lines.join('\n'), url: firstSpec.url };
}
