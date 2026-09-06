import { describe, it, expect } from 'vitest';
import { splitIngredient } from '../src/lib/client/ingredients';

describe('ingredients – mängd + vara', () => {
  it.each([
    ['500 g köttfärs', 'Köttfärs', '500 g'],
    ['2 msk olivolja', 'Olivolja', '2 msk'],
    ['1 dl grädde', 'Grädde', '1 dl'],
    ['0,5 dl mjölk', 'Mjölk', '0,5 dl'],
    ['1 ½ dl vatten', 'Vatten', '1 ½ dl'],
    ['½ citron', 'Citron', '½'],
    ['1-2 tsk salt', 'Salt', '1-2 tsk'],
    ['2 st ägg', 'Ägg', '2 st'],
    ['3 ägg', 'Ägg', '3'],
    ['1 gul lök', 'Gul lök', '1'],
    ['2 vitlöksklyftor', 'Vitlöksklyftor', '2'],
    ['1 burk krossade tomater', 'Krossade tomater', '1 burk'],
    ['1 förp (400 g) krossade tomater', 'Krossade tomater', '1 förp (400 g)'],
    ['ca 800 g potatis', 'Potatis', '800 g'],
    ['2 dl  ris,  gärna basmati', 'Ris, gärna basmati', '2 dl']
  ])('%s → %s · %s', (line, name, qty) => {
    expect(splitIngredient(line)).toEqual({ name, qty });
  });

  it('rader utan mängd lämnas orörda (men får stor bokstav)', () => {
    expect(splitIngredient('salt och peppar')).toEqual({ name: 'Salt och peppar', qty: null });
    expect(splitIngredient('Mjölk')).toEqual({ name: 'Mjölk', qty: null });
  });

  it('enbart en mängd utan vara blir namnet som det är', () => {
    expect(splitIngredient('100 g')).toEqual({ name: '100 g', qty: null });
  });

  it('"g" matchas inte inne i ord som "gula"', () => {
    expect(splitIngredient('2 gula lökar')).toEqual({ name: 'Gula lökar', qty: '2' });
  });
});
