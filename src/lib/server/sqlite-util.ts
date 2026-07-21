/** Rena SQLite-hjälpare utan sidoeffekter (ingen DB öppnas, ingen $env).
 *  Ligger separat så tjänstelagret kan importeras i tester utan att
 *  db.ts-singletonen körs. */

export const now = (): string => new Date().toISOString();

/**
 * SQLite `datetime('now')` lagrar UTC som "YYYY-MM-DD HH:MM:SS" (utan Z).
 * Webbläsare tolkar det som LOKAL tid → tidsförskjutning. Normalisera till
 * ISO-8601 UTC innan värden skickas till klienten. Redan-ISO-värden (våra
 * egna now()-anrop) lämnas orörda.
 */
export function toIso(s: string | null): string | null {
  if (!s) return s;
  if (s.includes('T')) return s;
  return s.replace(' ', 'T') + 'Z';
}

/** True om felet är ett SQLite unik-/constraint-brott (t.ex. dubblettskyddet). */
export function isUniqueViolation(e: unknown): boolean {
  return (
    typeof e === 'object' &&
    e !== null &&
    'code' in e &&
    String((e as { code: unknown }).code).startsWith('SQLITE_CONSTRAINT')
  );
}
