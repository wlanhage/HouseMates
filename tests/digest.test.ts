import { describe, it, expect } from 'vitest';
import { buildDigest, listNames, whenLabel } from '../src/lib/server/digest';

const shop = (verb: string, id: string, name: string) => ({
  type: `shopping.${verb}`,
  entity_id: id,
  payload: { name }
});

describe('notis-digest – en läsbar push per tyst-fönster', () => {
  it('flera avbockade varor → rubrik med antal, namn i brödtexten', () => {
    const acts = ['Mjölk', 'Bröd', 'Kaffe', 'Smör', 'Ägg', 'Juice'].map((n, i) => shop('checked', `s${i}`, n));
    expect(buildDigest('William', acts)).toEqual({
      title: 'William handlade 6 varor',
      body: 'Mjölk, Bröd, Kaffe, Smör, Ägg + 1 till',
      url: 'inkop'
    });
  });

  it('en enda vara → namnet i rubriken, tom brödtext', () => {
    expect(buildDigest('William', [shop('checked', 's1', 'Mjölk')])).toEqual({
      title: 'William handlade Mjölk',
      body: '',
      url: 'inkop'
    });
  });

  it('bockad och avbockad inom fönstret nettas bort → ingen notis', () => {
    expect(buildDigest('William', [shop('checked', 's1', 'Mjölk'), shop('unchecked', 's1', 'Mjölk')])).toBeNull();
    expect(buildDigest('William', [shop('added', 's2', 'Ägg'), shop('deleted', 's2', 'Ägg')])).toBeNull();
  });

  it('tillagd och sedan bockad räknas som handlad, inte tillagd', () => {
    expect(buildDigest('William', [shop('added', 's1', 'Mjölk'), shop('checked', 's1', 'Mjölk')])?.title).toBe(
      'William handlade Mjölk'
    );
  });

  it('flera slags saker → "Nytt från", en rad per grupp, länk till viktigaste', () => {
    const acts = [
      shop('checked', 's1', 'Mjölk'),
      shop('checked', 's2', 'Bröd'),
      { type: 'chore.done', entity_id: 'c1', payload: { title: 'Byta sängkläder' } },
      shop('added', 's3', 'Ägg')
    ];
    expect(buildDigest('William', acts)).toEqual({
      title: 'Nytt från William',
      body: 'Handlade: Mjölk och Bröd\nStädade: Byta sängkläder\nLa till på listan: Ägg',
      url: 'inkop'
    });
  });

  it('städ ensamt → "städade" med sysslan i brödtexten, länk till att göra', () => {
    expect(buildDigest('Matilda', [{ type: 'chore.done', entity_id: 'c1', payload: { title: 'Dammsuga' } }])).toEqual({
      title: 'Matilda städade',
      body: 'Dammsuga',
      url: 'todo'
    });
  });

  it('uppgift skapad och klarad i samma fönster → klarade av', () => {
    const acts = [
      { type: 'todo.created', entity_id: 't1', payload: { title: 'Boka besiktning' } },
      { type: 'todo.done', entity_id: 't1', payload: { title: 'Boka besiktning' } }
    ];
    expect(buildDigest('Matilda', acts)?.title).toBe('Matilda klarade av Boka besiktning');
  });

  it('kalenderhändelse med tid i brödtexten', () => {
    const d = buildDigest('William', [
      { type: 'event.created', entity_id: 'e1', payload: { title: 'Träning', start: '2026-09-16T10:00:00.000Z' } }
    ]);
    expect(d?.title).toBe('William la in Träning i kalendern');
    expect(d?.body).toMatch(/ons.*16 sep.*12:00/);
    expect(d?.url).toBe('kalender');
  });

  it('arkivering ignoreras', () => {
    expect(buildDigest('William', [{ type: 'shopping.archived', entity_id: '', payload: { count: 3 } }])).toBeNull();
  });

  it('listNames: "och" för två, "+ n till" över max', () => {
    expect(listNames(['A', 'B'])).toBe('A och B');
    expect(listNames(['A', 'B', 'C'])).toBe('A, B, C');
    expect(listNames(['A', 'B', 'C', 'D', 'E', 'F', 'G'])).toBe('A, B, C, D, E + 2 till');
  });

  it('whenLabel: heldag utan klockslag', () => {
    expect(whenLabel('2026-09-16')).toMatch(/ons.*16 sep/);
    expect(whenLabel('2026-09-16')).not.toMatch(/\d{2}:\d{2}/);
    expect(whenLabel(null)).toBe('');
  });
});
