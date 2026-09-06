/**
 * Dela en ingrediensrad ("500 g köttfärs") i mängd + vara, så att recept
 * hamnar på inköpslistan som "Köttfärs · 500 g" och dubblettregeln (som
 * jämför namnet) fortsätter fungera. Rader utan mängd lämnas orörda.
 */

export interface SplitIngredient {
  name: string;
  qty: string | null;
}

// Längsta först så att t.ex. "dl" inte matchas som "d" + rest.
const UNITS = [
  'förpackningar',
  'förpackning',
  'portioner',
  'stycken',
  'flaskor',
  'flaska',
  'skivor',
  'klyftor',
  'kvistar',
  'burkar',
  'droppar',
  'paket',
  'påsar',
  'krukor',
  'klyfta',
  'skiva',
  'kvist',
  'kruka',
  'knippe',
  'tärning',
  'bitar',
  'förp',
  'burk',
  'påse',
  'nypa',
  'port',
  'blad',
  'msk',
  'tsk',
  'krm',
  'bit',
  'ark',
  'kg',
  'hg',
  'dl',
  'cl',
  'ml',
  'cm',
  'st',
  'g',
  'l'
];

const NUM = '(?:\\d+(?:[.,]\\d+)?(?:\\s*\\/\\s*\\d+)?|[½¼¾⅓⅔⅛])';
const RE = new RegExp(
  '^(?:ca\\.?|cirka)?\\s*' +
    `(?<num>${NUM}(?:\\s*[-–]\\s*${NUM})?(?:\\s+[½¼¾⅓⅔⅛])?)` +
    `(?:\\s*(?<unit>${UNITS.join('|')})\\.?(?=\\s|$|\\())?` +
    '\\s*(?<paren>\\([^)]*\\))?' +
    '\\s*(?<rest>.*)$',
  'i'
);

const capitalize = (s: string): string => s.charAt(0).toUpperCase() + s.slice(1);

export function splitIngredient(line: string): SplitIngredient {
  const text = line.replace(/\s+/g, ' ').trim();
  const m = RE.exec(text);
  const rest = m?.groups?.rest?.trim();
  if (!m || !rest) return { name: capitalize(text), qty: null };
  const qty = [m.groups!.num.replace(/\s+/g, ' ').trim(), m.groups!.unit?.toLowerCase(), m.groups!.paren]
    .filter(Boolean)
    .join(' ');
  return { name: capitalize(rest), qty };
}
