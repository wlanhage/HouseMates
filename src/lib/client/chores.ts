/** Städsysslornas intervall och sista dag (rent, testbart). */
import { addDaysStr, localDate } from './dates';
import type { Chore } from '$lib/types';

export type IntervalUnit = 'veckor' | 'dagar';

export interface ChoreInput {
  title: string;
  assignee: string | null;
  interval_days: number | null;
}

/** Sista dag: räknas från när sysslan faktiskt gjordes, så intervallet aldrig blir längre än angivet. */
export function choreDueDate(
  chore: Pick<Chore, 'interval_days' | 'last_done_at' | 'created_at'>
): string | null {
  if (!chore.interval_days) return null;
  return addDaysStr(localDate(chore.last_done_at ?? chore.created_at), chore.interval_days);
}

function ordinal(n: number): string {
  const lastTwo = n % 100;
  const suffix = [1, 2].includes(n % 10) && lastTwo !== 11 && lastTwo !== 12 ? 'a' : 'e';
  return `${n}:${suffix}`;
}

/** "varje vecka", "varannan vecka", "var 3:e vecka", "var 10:e dag" */
export function intervalLabel(days: number): string {
  const [count, one] = days % 7 === 0 ? [days / 7, 'vecka'] : [days, 'dag'];
  if (count === 1) return `varje ${one}`;
  if (count === 2) return `varannan ${one}`;
  return `var ${ordinal(count)} ${one}`;
}

export function splitInterval(days: number | null): { count: string; unit: IntervalUnit } {
  if (!days) return { count: '', unit: 'veckor' };
  return days % 7 === 0 ? { count: String(days / 7), unit: 'veckor' } : { count: String(days), unit: 'dagar' };
}

export function intervalDays(count: string, unit: IntervalUnit): number | null {
  const n = Math.floor(Number(count));
  if (!Number.isFinite(n) || n < 1) return null;
  return unit === 'veckor' ? n * 7 : n;
}
