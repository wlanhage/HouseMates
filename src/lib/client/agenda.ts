/**
 * Bygg agenda: gruppera events per dag. Flerdagarsevent dyker upp under varje
 * berörd dag med "dag X av Y" (spec §12.2). Ren modul → testbar.
 */
import { localDate, addDaysStr, daysBetween } from './dates';
import type { CalendarEvent } from '$lib/types';

export interface AgendaEntry {
  event: CalendarEvent;
  dayIndex: number; // 1-baserat
  dayCount: number;
  multiDay: boolean;
}
export interface AgendaDay {
  date: string;
  entries: AgendaEntry[];
}

/** Första och sista lokala dag ett event berör (heldag: end exklusivt). */
export function eventSpan(e: CalendarEvent): { first: string; last: string } {
  if (e.allDay) {
    const first = e.start;
    let last = addDaysStr(e.end, -1);
    if (last < first) last = first;
    return { first, last };
  }
  const first = localDate(e.start);
  // sista dag = slut minus 1 ms, så event som slutar 00:00 inte räknar nästa dag
  let last = localDate(new Date(new Date(e.end).getTime() - 1).toISOString());
  if (last < first) last = first;
  return { first, last };
}

export function buildAgenda(evs: CalendarEvent[], fromDay: string, toDay: string): AgendaDay[] {
  const spans = evs.map((e) => ({ e, ...eventSpan(e) }));
  const out: AgendaDay[] = [];
  const n = daysBetween(fromDay, toDay);
  for (let i = 0; i <= n; i++) {
    const date = addDaysStr(fromDay, i);
    const entries: AgendaEntry[] = [];
    for (const s of spans) {
      if (date >= s.first && date <= s.last) {
        const dayCount = daysBetween(s.first, s.last) + 1;
        entries.push({
          event: s.e,
          dayIndex: daysBetween(s.first, date) + 1,
          dayCount,
          multiDay: dayCount > 1
        });
      }
    }
    entries.sort((a, b) => {
      if (a.event.allDay !== b.event.allDay) return a.event.allDay ? -1 : 1; // heldag överst
      if (a.event.allDay) return a.event.title.localeCompare(b.event.title);
      return a.event.start.localeCompare(b.event.start); // sedan tidsordning
    });
    if (entries.length) out.push({ date, entries });
  }
  return out;
}
