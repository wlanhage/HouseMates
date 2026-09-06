/** Datum-/tidshjälpare för visning i lokal tidszon (spec §12.1). */
const TZ = 'Europe/Stockholm';

const ymdFmt = new Intl.DateTimeFormat('sv-SE', {
  timeZone: TZ,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit'
});

/** YYYY-MM-DD i lokal tidszon. */
export function ymd(d: Date = new Date()): string {
  return ymdFmt.format(d); // sv-SE → "2026-07-21"
}

export function todayStr(): string {
  return ymd();
}
export function tomorrowStr(): string {
  return ymd(new Date(Date.now() + 86_400_000));
}

/** Formatera ett rent datum (YYYY-MM-DD) som "24 dec". */
export function fmtDate(dateStr: string): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return new Intl.DateTimeFormat('sv-SE', { day: 'numeric', month: 'short', timeZone: 'UTC' })
    .format(dt)
    .replace('.', '');
}

export type DueKind = 'overdue' | 'today' | 'tomorrow' | 'future';

export function dueLabel(due: string): { text: string; kind: DueKind } {
  const today = todayStr();
  const tomorrow = tomorrowStr();
  if (due < today) return { text: 'Försenad', kind: 'overdue' };
  if (due === today) return { text: 'Idag', kind: 'today' };
  if (due === tomorrow) return { text: 'Imorgon', kind: 'tomorrow' };
  return { text: fmtDate(due), kind: 'future' };
}

/** "nyss", "20 min sedan", "3 tim sedan", annars datum. */
export function relativeTime(iso: string): string {
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.floor(diff / 60_000);
  if (min < 1) return 'nyss';
  if (min < 60) return `${min} min sedan`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} tim sedan`;
  const days = Math.floor(h / 24);
  if (days === 1) return 'igår';
  if (days < 7) return `${days} dgr sedan`;
  return fmtDate(ymd(new Date(iso)));
}

/** "idag" / "igår" / "N dagar sedan" – för städsysslornas "senast gjort". */
export function daysAgoLabel(iso: string): string {
  const days = daysBetween(ymd(new Date(iso)), ymd());
  if (days <= 0) return 'idag';
  if (days === 1) return 'igår';
  return `${days} dagar sedan`;
}

/** Klockslag HH:MM i lokal tidszon för en ISO-tidsstämpel. */
export function hhmm(iso: string): string {
  return new Intl.DateTimeFormat('sv-SE', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: TZ
  }).format(new Date(iso));
}

/** Lokalt datum (YYYY-MM-DD) för en ISO-tidsstämpel. */
export function localDate(iso: string): string {
  return ymd(new Date(iso));
}

export function addDaysStr(dateStr: string, n: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  return ymd(new Date(Date.UTC(y, m - 1, d + n)));
}

/** Antal dagar mellan två rena datum (b − a). */
export function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = a.split('-').map(Number);
  const [by, bm, bd] = b.split('-').map(Number);
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000);
}

/** Rubrik för en dag i agendan: "Idag" / "Imorgon" / "mån 15 jul". */
export function dayHeading(dateStr: string): string {
  const today = todayStr();
  if (dateStr === today) return 'Idag';
  if (dateStr === tomorrowStr()) return 'Imorgon';
  if (dateStr === addDaysStr(today, -1)) return 'Igår';
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return new Intl.DateTimeFormat('sv-SE', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: 'UTC'
  })
    .format(dt)
    .replace(/\./g, '');
}
