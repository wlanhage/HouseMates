/**
 * ICS → eventrader för Deno/Edge (porterad från src/lib/server/caldav/ics.ts,
 * samma logik som är verifierad av vitest-sviten i tests/ics.test.ts).
 */
// @ts-expect-error npm-import i Deno saknar typer här
import ICAL from 'npm:ical.js@2.1.0';

export interface EventRow {
  caldav_uid: string;
  recurrence_id: string;
  title: string;
  location: string | null;
  notes: string | null;
  all_day: boolean;
  start_ts: string | null;
  end_ts: string | null;
  start_date: string | null;
  end_date: string | null;
  is_recurring: boolean;
}

const pad = (n: number) => String(n).padStart(2, '0');
const ymd = (t: any): string => `${t.year}-${pad(t.month)}-${pad(t.day)}`;

function addDays(dateStr: string, days: number): string {
  const [y, m, d] = dateStr.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + days));
  return `${dt.getUTCFullYear()}-${pad(dt.getUTCMonth() + 1)}-${pad(dt.getUTCDate())}`;
}

function registerTimezones(vcal: any): void {
  for (const vtz of vcal.getAllSubcomponents('vtimezone')) {
    const tzid = vtz.getFirstPropertyValue('tzid');
    if (tzid && !ICAL.TimezoneService.has(tzid)) ICAL.TimezoneService.register(vtz);
  }
}

const recIdOf = (t: any): string => (t.isDate ? ymd(t) : t.toJSDate().toISOString());
const str = (v: unknown): string | null => (v == null ? null : String(v));

function makeRow(
  uid: string,
  recurrenceId: string,
  isRecurring: boolean,
  title: string,
  location: string | null,
  notes: string | null,
  start: any,
  end: any | null
): EventRow {
  if (start.isDate) {
    const start_date = ymd(start);
    let end_date = end ? ymd(end) : addDays(start_date, 1);
    if (end_date <= start_date) end_date = addDays(start_date, 1);
    return {
      caldav_uid: uid,
      recurrence_id: recurrenceId,
      title,
      location,
      notes,
      all_day: true,
      start_ts: null,
      end_ts: null,
      start_date,
      end_date,
      is_recurring: isRecurring
    };
  }
  const start_ts = start.toJSDate().toISOString();
  let end_ts = end
    ? end.toJSDate().toISOString()
    : new Date(start.toJSDate().getTime() + 3_600_000).toISOString();
  if (new Date(end_ts).getTime() <= new Date(start_ts).getTime()) {
    end_ts = new Date(new Date(start_ts).getTime() + 3_600_000).toISOString();
  }
  return {
    caldav_uid: uid,
    recurrence_id: recurrenceId,
    title,
    location,
    notes,
    all_day: false,
    start_ts,
    end_ts,
    start_date: null,
    end_date: null,
    is_recurring: isRecurring
  };
}

export interface EventFields {
  uid: string;
  title: string;
  allDay: boolean;
  start: string; // ISO-ts (tidsatt) eller YYYY-MM-DD (heldag)
  end: string; // heldag: exklusivt datum
  location?: string | null;
  notes?: string | null;
}

function timeFrom(value: string, allDay: boolean): any {
  if (allDay) return ICAL.Time.fromDateString(value);
  return ICAL.Time.fromJSDate(new Date(value), true); // true = UTC
}

/** Bygg minimal VCALENDAR för ett nytt event (spec §9.4 create). */
export function buildVCalendar(fields: EventFields): string {
  const vcal = new ICAL.Component(['vcalendar', [], []]);
  vcal.updatePropertyWithValue('version', '2.0');
  vcal.updatePropertyWithValue('prodid', '-//Planeraren//SV');

  const vevent = new ICAL.Component('vevent');
  const event = new ICAL.Event(vevent);
  event.uid = fields.uid;
  event.summary = fields.title;
  event.startDate = timeFrom(fields.start, fields.allDay);
  event.endDate = timeFrom(fields.end, fields.allDay);
  if (fields.location) event.location = fields.location;
  if (fields.notes) event.description = fields.notes;
  vevent.updatePropertyWithValue('dtstamp', ICAL.Time.fromJSDate(new Date(), true));
  vevent.updatePropertyWithValue('sequence', 0);

  vcal.addSubcomponent(vevent);
  return vcal.toString();
}

/** Uppdatera ENDAST ändrade fält; bevara okända (VALARM m.m.) (spec §9.4). */
export function updateRawIcs(rawIcs: string, changes: Partial<Omit<EventFields, 'uid'>>): string {
  const vcal = new ICAL.Component(ICAL.parse(rawIcs));
  const vevents = vcal.getAllSubcomponents('vevent');
  const master = vevents.find((v: any) => !v.hasProperty('recurrence-id')) ?? vevents[0];
  const event = new ICAL.Event(master);

  if (changes.title !== undefined) event.summary = changes.title;
  if (changes.location !== undefined) {
    if (changes.location) event.location = changes.location;
    else master.removeProperty('location');
  }
  if (changes.notes !== undefined) {
    if (changes.notes) event.description = changes.notes;
    else master.removeProperty('description');
  }
  const allDay = changes.allDay ?? event.startDate.isDate;
  if (changes.start !== undefined) event.startDate = timeFrom(changes.start, allDay);
  if (changes.end !== undefined) event.endDate = timeFrom(changes.end, allDay);

  master.removeProperty('dtstamp');
  master.updatePropertyWithValue('dtstamp', ICAL.Time.fromJSDate(new Date(), true));
  const seq = Number(master.getFirstPropertyValue('sequence') ?? 0);
  master.updatePropertyWithValue('sequence', seq + 1);

  return vcal.toString();
}

export function parseResource(ics: string, windowStart: Date, windowEnd: Date): EventRow[] {
  const vcal = new ICAL.Component(ICAL.parse(ics));
  registerTimezones(vcal);

  const vevents = vcal.getAllSubcomponents('vevent');
  const masters = vevents.filter((v: any) => !v.hasProperty('recurrence-id'));
  const exceptions = vevents.filter((v: any) => v.hasProperty('recurrence-id'));
  const rows: EventRow[] = [];

  for (const masterComp of masters) {
    const event = new ICAL.Event(masterComp);
    for (const exComp of exceptions) {
      if (exComp.getFirstPropertyValue('uid') === event.uid) {
        event.relateException(new ICAL.Event(exComp));
      }
    }

    if (event.isRecurring()) {
      const it = event.iterator();
      let next: any;
      let guard = 0;
      while ((next = it.next()) && guard++ < 2000) {
        if (next.toJSDate().getTime() > windowEnd.getTime()) break;
        const details = event.getOccurrenceDetails(next);
        if (details.endDate.toJSDate().getTime() < windowStart.getTime()) continue;
        const item = details.item;
        rows.push(
          makeRow(
            event.uid,
            recIdOf(next),
            true,
            item.summary ?? '',
            str(item.location),
            str(item.description),
            details.startDate,
            details.endDate
          )
        );
      }
    } else {
      rows.push(
        makeRow(
          event.uid,
          '',
          false,
          event.summary ?? '',
          str(event.location),
          str(event.description),
          event.startDate,
          event.endDate
        )
      );
    }
  }
  return rows;
}
