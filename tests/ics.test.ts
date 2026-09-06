import { describe, it, expect } from 'vitest';
import { parseResource, buildVCalendar, updateRawIcs } from '../src/lib/server/caldav/ics';

const VTIMEZONE = [
  'BEGIN:VTIMEZONE',
  'TZID:Europe/Stockholm',
  'BEGIN:DAYLIGHT',
  'TZOFFSETFROM:+0100',
  'TZOFFSETTO:+0200',
  'TZNAME:CEST',
  'DTSTART:19700329T020000',
  'RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU',
  'END:DAYLIGHT',
  'BEGIN:STANDARD',
  'TZOFFSETFROM:+0200',
  'TZOFFSETTO:+0100',
  'TZNAME:CET',
  'DTSTART:19701025T030000',
  'RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU',
  'END:STANDARD',
  'END:VTIMEZONE'
].join('\r\n');

function vcal(...vevents: string[]): string {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//test//EN',
    VTIMEZONE,
    ...vevents,
    'END:VCALENDAR'
  ].join('\r\n');
}

const WIN_START = new Date('2026-01-01T00:00:00Z');
const WIN_END = new Date('2027-01-01T00:00:00Z');
const parse = (ics: string) => parseResource(ics, WIN_START, WIN_END);

describe('ics.ts – parsning (spec §15)', () => {
  it('(a) tidsatt event med TZID → UTC', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:a@test',
        'DTSTART;TZID=Europe/Stockholm:20260715T140000',
        'DTEND;TZID=Europe/Stockholm:20260715T150000',
        'SUMMARY:Möte',
        'LOCATION:Kontoret',
        'END:VEVENT'
      ].join('\r\n')
    );
    const rows = parse(ics);
    expect(rows).toHaveLength(1);
    const r = rows[0];
    expect(r.all_day).toBe(0);
    expect(r.start_ts).toBe('2026-07-15T12:00:00.000Z'); // CEST = UTC+2
    expect(r.end_ts).toBe('2026-07-15T13:00:00.000Z');
    expect(r.title).toBe('Möte');
    expect(r.location).toBe('Kontoret');
    expect(r.is_recurring).toBe(false);
  });

  it('(b) heldag en dag → end_date exklusivt', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:b@test',
        'DTSTART;VALUE=DATE:20261224',
        'DTEND;VALUE=DATE:20261225',
        'SUMMARY:Julafton',
        'END:VEVENT'
      ].join('\r\n')
    );
    const r = parse(ics)[0];
    expect(r.all_day).toBe(1);
    expect(r.start_date).toBe('2026-12-24');
    expect(r.end_date).toBe('2026-12-25');
    expect(r.start_ts).toBeNull();
  });

  it('(c) heldag flera dagar → exklusivt slut', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:c@test',
        'DTSTART;VALUE=DATE:20260701',
        'DTEND;VALUE=DATE:20260704',
        'SUMMARY:Semester',
        'END:VEVENT'
      ].join('\r\n')
    );
    const r = parse(ics)[0];
    expect(r.start_date).toBe('2026-07-01');
    expect(r.end_date).toBe('2026-07-04'); // täcker 1,2,3
  });

  it('(c2) heldag utan DTEND → +1 dag', () => {
    const ics = vcal(
      ['BEGIN:VEVENT', 'UID:c2@test', 'DTSTART;VALUE=DATE:20260701', 'SUMMARY:Dag', 'END:VEVENT'].join(
        '\r\n'
      )
    );
    const r = parse(ics)[0];
    expect(r.start_date).toBe('2026-07-01');
    expect(r.end_date).toBe('2026-07-02');
  });

  it('(d) tidsatt över midnatt (lokal tid)', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:d@test',
        'DTSTART;TZID=Europe/Stockholm:20260715T230000',
        'DTEND;TZID=Europe/Stockholm:20260716T010000',
        'SUMMARY:Nattpass',
        'END:VEVENT'
      ].join('\r\n')
    );
    const r = parse(ics)[0];
    expect(r.start_ts).toBe('2026-07-15T21:00:00.000Z');
    expect(r.end_ts).toBe('2026-07-15T23:00:00.000Z');
  });

  it('(e) RRULE veckovis med EXDATE', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:e@test',
        'DTSTART;TZID=Europe/Stockholm:20260706T090000',
        'DTEND;TZID=Europe/Stockholm:20260706T093000',
        'RRULE:FREQ=WEEKLY;COUNT=4',
        'EXDATE;TZID=Europe/Stockholm:20260713T090000',
        'SUMMARY:Standup',
        'END:VEVENT'
      ].join('\r\n')
    );
    const rows = parse(ics);
    const startDates = rows.map((r) => r.start_ts!.slice(0, 10));
    expect(rows.every((r) => r.is_recurring)).toBe(true);
    expect(startDates).toContain('2026-07-06');
    expect(startDates).toContain('2026-07-20');
    expect(startDates).toContain('2026-07-27');
    expect(startDates).not.toContain('2026-07-13'); // EXDATE
    expect(rows).toHaveLength(3);
  });

  it('(f) RRULE med override (RECURRENCE-ID)', () => {
    const ics = vcal(
      [
        'BEGIN:VEVENT',
        'UID:f@test',
        'DTSTART;TZID=Europe/Stockholm:20260706T090000',
        'DTEND;TZID=Europe/Stockholm:20260706T093000',
        'RRULE:FREQ=WEEKLY;COUNT=3',
        'SUMMARY:Standup',
        'END:VEVENT'
      ].join('\r\n'),
      [
        'BEGIN:VEVENT',
        'UID:f@test',
        'RECURRENCE-ID;TZID=Europe/Stockholm:20260713T090000',
        'DTSTART;TZID=Europe/Stockholm:20260713T100000',
        'DTEND;TZID=Europe/Stockholm:20260713T103000',
        'SUMMARY:Standup (flyttat)',
        'END:VEVENT'
      ].join('\r\n')
    );
    const rows = parse(ics);
    expect(rows).toHaveLength(3);
    const moved = rows.find((r) => r.recurrence_id === '2026-07-13T07:00:00.000Z');
    expect(moved).toBeTruthy();
    expect(moved!.title).toBe('Standup (flyttat)');
    expect(moved!.start_ts).toBe('2026-07-13T08:00:00.000Z'); // flyttad till 10:00 CEST
  });
});

describe('ics.ts – serialisering (spec §15)', () => {
  it('buildVCalendar tidsatt → round-trip', () => {
    const ics = buildVCalendar({
      uid: 'new@test',
      title: 'Nytt möte',
      allDay: false,
      start: '2026-07-15T12:00:00.000Z',
      end: '2026-07-15T13:00:00.000Z',
      location: 'Hemma'
    });
    const r = parseResource(ics, WIN_START, WIN_END)[0];
    expect(r.title).toBe('Nytt möte');
    expect(r.all_day).toBe(0);
    expect(r.start_ts).toBe('2026-07-15T12:00:00.000Z');
    expect(r.end_ts).toBe('2026-07-15T13:00:00.000Z');
    expect(r.location).toBe('Hemma');
  });

  it('buildVCalendar heldag → rena datum, exklusivt slut', () => {
    const ics = buildVCalendar({
      uid: 'h@test',
      title: 'Semester',
      allDay: true,
      start: '2026-07-01',
      end: '2026-07-04'
    });
    const r = parseResource(ics, WIN_START, WIN_END)[0];
    expect(r.all_day).toBe(1);
    expect(r.start_date).toBe('2026-07-01');
    expect(r.end_date).toBe('2026-07-04');
  });

  it('updateRawIcs ändrar bara titeln och bevarar okända fält (VALARM)', () => {
    const original = vcal(
      [
        'BEGIN:VEVENT',
        'UID:u@test',
        'DTSTART;TZID=Europe/Stockholm:20260715T140000',
        'DTEND;TZID=Europe/Stockholm:20260715T150000',
        'SUMMARY:Gammal',
        'BEGIN:VALARM',
        'ACTION:DISPLAY',
        'TRIGGER:-PT15M',
        'DESCRIPTION:Påminnelse',
        'END:VALARM',
        'END:VEVENT'
      ].join('\r\n')
    );
    const updated = updateRawIcs(original, { title: 'Ny titel' });
    expect(updated).toContain('SUMMARY:Ny titel');
    expect(updated).not.toContain('SUMMARY:Gammal');
    expect(updated).toContain('BEGIN:VALARM'); // okänt fält bevarat
    expect(updated).toContain('TRIGGER:-PT15M');
    // tiden orörd
    const r = parseResource(updated, WIN_START, WIN_END)[0];
    expect(r.start_ts).toBe('2026-07-15T12:00:00.000Z');
  });
});

describe('ics.ts – "för vem" (X-PLANERAREN-FOR)', () => {
  it('skrivs vid create, läses vid parse, ändras/tas bort vid update', () => {
    const ics = buildVCalendar({
      uid: 'app-william-1',
      title: 'Träning',
      allDay: false,
      start: '2026-06-01T17:00:00.000Z',
      end: '2026-06-01T18:00:00.000Z',
      assignee: 'william'
    });
    expect(ics).toContain('X-PLANERAREN-FOR:william');
    expect(parse(ics)[0].assignee).toBe('william');

    const changed = updateRawIcs(ics, { assignee: 'both' });
    expect(parse(changed)[0].assignee).toBe('both');
    expect(parse(changed)[0].title).toBe('Träning');

    const removed = updateRawIcs(changed, { assignee: null });
    expect(parse(removed)[0].assignee).toBeNull();
  });

  it('event utan markering (t.ex. från Apple Kalender) → null', () => {
    const ics = vcal(
      ['BEGIN:VEVENT', 'UID:x1', 'DTSTART;VALUE=DATE:20260601', 'DTEND;VALUE=DATE:20260602', 'SUMMARY:Bortrest', 'END:VEVENT'].join('\r\n')
    );
    expect(parse(ics)[0].assignee).toBeNull();
  });
});
