/**
 * Rena hjälpare för notis-workern (spec §11) – ingen DB/$env, testbara (§15):
 * tysta timmar-beräkning. Digesten ligger i digest.ts.
 */
const DEFAULT_TZ = 'Europe/Stockholm';

const toMin = (hhmm: string): number => {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
};

/** Är klockslaget (HH:MM) inom [from, to)? Hanterar midnattsvridning. */
export function inQuietWindow(hhmm: string, from: string, to: string): boolean {
  const t = toMin(hhmm);
  const f = toMin(from);
  const e = toMin(to);
  if (f === e) return false;
  if (f < e) return t >= f && t < e;
  return t >= f || t < e;
}

/** HH:MM i lokal tidszon för en tidpunkt. */
export function localHHMM(date: Date, tz: string = DEFAULT_TZ): string {
  return new Intl.DateTimeFormat('sv-SE', {
    timeZone: tz,
    hour: '2-digit',
    minute: '2-digit',
    hour12: false
  }).format(date);
}

/** Nästa UTC-tidpunkt då quiet_to (lokal tid) inträffar efter `after`. */
export function nextQuietTo(after: Date, quietTo: string, tz: string = DEFAULT_TZ): string {
  const [yy, mm, dd] = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })
    .format(after)
    .split('-')
    .map(Number);
  const [qh, qm] = quietTo.split(':').map(Number);

  const wallToUtc = (y: number, m: number, d: number): Date => {
    const guess = Date.UTC(y, m - 1, d, qh, qm);
    const p = Object.fromEntries(
      new Intl.DateTimeFormat('en-US', {
        timeZone: tz,
        hour12: false,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
      })
        .formatToParts(new Date(guess))
        .map((x) => [x.type, x.value])
    );
    const hour = p.hour === '24' ? 0 : Number(p.hour);
    const asUtc = Date.UTC(
      Number(p.year),
      Number(p.month) - 1,
      Number(p.day),
      hour,
      Number(p.minute),
      Number(p.second)
    );
    return new Date(guess - (asUtc - guess));
  };

  let candidate = wallToUtc(yy, mm, dd);
  if (candidate.getTime() <= after.getTime()) {
    const next = new Date(Date.UTC(yy, mm - 1, dd + 1));
    candidate = wallToUtc(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate());
  }
  return candidate.toISOString();
}
