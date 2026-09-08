/** Månadsrutnät för kalenderns rutnätsvy (rent, testbart). Veckan börjar på måndag. */

export interface MonthCell {
  date: string | null; // null = utfyllnad före den 1:a
  day: number;
}

export interface Month {
  year: number;
  month: number; // 1–12
  label: string; // "September 2026"
  first: string; // YYYY-MM-DD
  last: string;
  cells: MonthCell[];
}

export const WEEKDAYS = ['mån', 'tis', 'ons', 'tor', 'fre', 'lör', 'sön'];

const pad = (n: number) => String(n).padStart(2, '0');

export function monthOf(dateStr: string): { year: number; month: number } {
  const [year, month] = dateStr.split('-').map(Number);
  return { year, month };
}

export function addMonths(year: number, month: number, n: number): { year: number; month: number } {
  const idx = year * 12 + (month - 1) + n;
  return { year: Math.floor(idx / 12), month: (idx % 12) + 1 };
}

export function buildMonth(year: number, month: number): Month {
  const daysInMonth = new Date(Date.UTC(year, month, 0)).getUTCDate();
  const firstWeekday = (new Date(Date.UTC(year, month - 1, 1)).getUTCDay() + 6) % 7; // 0 = måndag
  const cells: MonthCell[] = Array.from({ length: firstWeekday }, () => ({ date: null, day: 0 }));
  for (let day = 1; day <= daysInMonth; day++) {
    cells.push({ date: `${year}-${pad(month)}-${pad(day)}`, day });
  }
  const raw = new Intl.DateTimeFormat('sv-SE', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(
    new Date(Date.UTC(year, month - 1, 1))
  );
  return {
    year,
    month,
    label: raw.charAt(0).toUpperCase() + raw.slice(1),
    first: `${year}-${pad(month)}-01`,
    last: `${year}-${pad(month)}-${pad(daysInMonth)}`,
    cells
  };
}
