/** Gruppering av aktivitetsflödet för hemskärmen (spec §12.2):
 *  samma aktör + typ inom 30 min slås ihop till en rad. */
import type { Activity } from '$lib/types';

const WINDOW = 30 * 60 * 1000;

interface Group {
  key: string;
  actor: string;
  type: string;
  entries: Activity[];
  newest: string;
}

export function groupActivity(items: Activity[]): Group[] {
  // Slå ihop ALLA rader med samma aktör + typ inom 30 min av gruppens senaste
  // rad – även om de inte ligger intill varandra i flödet (interfolierade
  // "la till"/"bockade av" ska ändå bli EN rad var).
  const open = new Map<string, Group>();
  const out: Group[] = [];
  for (const a of items) {
    const bucket = `${a.actor}|${a.type}`;
    const g = open.get(bucket);
    if (g && new Date(g.newest).getTime() - new Date(a.created_at).getTime() <= WINDOW) {
      g.entries.push(a);
    } else {
      const ng: Group = {
        key: `${a.id}`,
        actor: a.actor,
        type: a.type,
        entries: [a],
        newest: a.created_at
      };
      open.set(bucket, ng);
      out.push(ng);
    }
  }
  return out;
}

const VERB: Record<string, string> = {
  'shopping.added': 'la till',
  'shopping.checked': 'bockade av',
  'shopping.unchecked': 'avmarkerade',
  'shopping.deleted': 'tog bort',
  'shopping.restored': 'återställde',
  'shopping.archived': 'tömde',
  'todo.created': 'skapade',
  'todo.done': 'bockade av',
  'todo.undone': 'återöppnade',
  'todo.deleted': 'tog bort',
  'todo.restored': 'återställde',
  'event.created': 'skapade eventet',
  'event.updated': 'ändrade eventet',
  'event.deleted': 'tog bort eventet',
  'event.restored': 'återställde eventet'
};

function noun(entityType: string, n: number): string {
  if (entityType === 'shopping') return n === 1 ? 'vara' : 'varor';
  if (entityType === 'todo') return n === 1 ? 'uppgift' : 'uppgifter';
  return n === 1 ? 'händelse' : 'händelser';
}

/** Bygg beskrivningstext för en grupp, t.ex. "la till 3 varor" eller "la till Mjölk". */
export function describeGroup(g: Group): string {
  const verb = VERB[g.type] ?? 'ändrade';
  const first = g.entries[0];
  const entity = first.entity_type;

  if (g.type === 'shopping.archived') {
    const count = g.entries.reduce((s, e) => s + Number((e.payload?.count as number) ?? 0), 0);
    return `${verb} ${count} avklarade`;
  }

  if (g.entries.length === 1) {
    const label = (first.payload?.name as string) ?? (first.payload?.title as string) ?? '';
    if (g.type.startsWith('event.')) return verb;
    return label ? `${verb} ${label}` : `${verb} en ${noun(entity, 1)}`;
  }
  return `${verb} ${g.entries.length} ${noun(entity, g.entries.length)}`;
}
