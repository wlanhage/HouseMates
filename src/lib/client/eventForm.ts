/**
 * Eventformulärets regler, utan UI (testbara):
 *  - tom tid = hela dagen ("Gym", "Bortrest"), ifylld tid = tidsatt – ingen toggle
 *  - tom sluttid = en timme efter start
 *  - tomt slutdatum = samma dag; ett slutdatum ger flera dagar
 */
import { addDaysStr, localDate, hhmm } from './dates';
import type { CalendarEvent } from '$lib/types';
import type { EventInput } from './data';

export interface EventFormFields {
  title: string;
  assignee: string | null;
  date: string; // YYYY-MM-DD
  endDate: string; // '' = samma dag
  startTime: string; // HH:MM, '' = hela dagen
  endTime: string; // HH:MM, '' = en timme efter start
  location: string;
  notes: string;
}

export type EventFormResult = { ok: true; input: EventInput } | { ok: false; error: string };

const HOUR = 3_600_000;

export function emptyFields(date: string): EventFormFields {
  return { title: '', assignee: 'both', date, endDate: '', startTime: '', endTime: '', location: '', notes: '' };
}

/** Fält från ett befintligt event (redigering). */
export function fieldsFrom(e: CalendarEvent): EventFormFields {
  const base = { title: e.title, assignee: e.assignee, location: e.location ?? '', notes: e.notes ?? '' };
  if (e.allDay) {
    const last = addDaysStr(e.end, -1); // lagrat exklusivt, visas inklusivt
    return { ...base, date: e.start, endDate: last !== e.start ? last : '', startTime: '', endTime: '' };
  }
  const date = localDate(e.start);
  const endDate = localDate(e.end);
  return { ...base, date, endDate: endDate !== date ? endDate : '', startTime: hhmm(e.start), endTime: hhmm(e.end) };
}

export function eventInputFrom(f: EventFormFields): EventFormResult {
  const title = f.title.trim();
  if (!title) return { ok: false, error: 'Ange en titel.' };
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.date)) return { ok: false, error: 'Ange ett datum.' };
  const lastDay = f.endDate || f.date;
  if (lastDay < f.date) return { ok: false, error: 'Slutdatum måste vara samma dag eller senare.' };

  const common = {
    title,
    location: f.location.trim() || null,
    notes: f.notes.trim() || null,
    assignee: f.assignee
  };

  if (!f.startTime) {
    return { ok: true, input: { ...common, allDay: true, start: f.date, end: addDaysStr(lastDay, 1) } };
  }

  const start = new Date(`${f.date}T${f.startTime}`); // lokal tid
  const end = f.endTime ? new Date(`${lastDay}T${f.endTime}`) : new Date(start.getTime() + HOUR);
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return { ok: false, error: 'Ogiltig tid.' };
  if (end.getTime() <= start.getTime()) return { ok: false, error: 'Sluttiden måste vara efter starttiden.' };
  return { ok: true, input: { ...common, allDay: false, start: start.toISOString(), end: end.toISOString() } };
}
