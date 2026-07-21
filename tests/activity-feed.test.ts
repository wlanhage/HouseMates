import { describe, it, expect } from 'vitest';
import { groupActivity, describeGroup } from '../src/lib/client/activityFeed';
import type { Activity } from '../src/lib/types';

let seq = 0;
const act = (type: string, label: string, minutesAgo: number): Activity => ({
  id: ++seq,
  type,
  actor: 'anna',
  entity_type: type.startsWith('shopping') ? 'shopping' : 'todo',
  entity_id: String(seq),
  payload: type === 'shopping.archived' ? { count: 2 } : { name: label },
  created_at: new Date(Date.UTC(2026, 6, 21, 12, 0, 0) - minutesAgo * 60_000).toISOString()
});

describe('aktivitetsflöde – gruppering (interfolierat)', () => {
  it('slår ihop samma typ även när de inte ligger intill varandra', () => {
    // Newest first, interfolierat: added, checked, added, checked, added
    const feed = [
      act('shopping.added', 'Ägg', 8),
      act('shopping.checked', 'Socker', 8),
      act('shopping.added', 'Kaffe', 8),
      act('shopping.checked', 'Kaffe', 9),
      act('shopping.added', 'Socker', 9)
    ];
    const groups = groupActivity(feed);
    // Bara två rader: en "la till", en "bockade av"
    expect(groups).toHaveLength(2);
    const added = groups.find((g) => g.type === 'shopping.added')!;
    const checked = groups.find((g) => g.type === 'shopping.checked')!;
    expect(added.entries).toHaveLength(3);
    expect(checked.entries).toHaveLength(2);
    expect(describeGroup(added)).toBe('la till 3 varor');
    expect(describeGroup(checked)).toBe('bockade av 2 varor');
  });

  it('enstaka händelse visar namnet', () => {
    const [g] = groupActivity([act('todo.created', 'Handla', 2)]);
    expect(describeGroup(g)).toBe('skapade Handla');
  });

  it('olika typer hålls isär (varor vs uppgifter)', () => {
    const groups = groupActivity([
      act('shopping.checked', 'Mjölk', 1),
      act('todo.done', 'Diska', 1)
    ]);
    expect(groups).toHaveLength(2);
  });
});
