import { describe, it, expect } from 'vitest';
import { eventInputFrom, fieldsFrom, emptyFields } from '../src/lib/client/eventForm';
import type { CalendarEvent } from '../src/lib/types';

const base = { ...emptyFields('2026-09-16'), title: 'Gym' };
const local = (s: string) => new Date(s).getTime(); // lokal tid, oberoende av testmaskinens tidszon

describe('eventformulär – tom tid = hela dagen, ingen toggle', () => {
  it('bara datum → heldag samma dag (slut exklusivt)', () => {
    const r = eventInputFrom(base);
    expect(r).toEqual({
      ok: true,
      input: { title: 'Gym', location: null, notes: null, assignee: 'both', allDay: true, start: '2026-09-16', end: '2026-09-17' }
    });
  });

  it('datum + slutdatum → flera dagar', () => {
    const r = eventInputFrom({ ...base, title: 'Bortrest', endDate: '2026-09-18' });
    expect(r.ok && r.input.allDay && r.input.end).toBe('2026-09-19');
  });

  it('starttid utan sluttid → en timme', () => {
    const r = eventInputFrom({ ...base, startTime: '10:00' });
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.input.allDay).toBe(false);
    expect(local(r.input.start)).toBe(local('2026-09-16T10:00'));
    expect(local(r.input.end)).toBe(local('2026-09-16T11:00'));
  });

  it('start- och sluttid', () => {
    const r = eventInputFrom({ ...base, startTime: '18:30', endTime: '20:00' });
    expect(r.ok && local(r.input.end)).toBe(local('2026-09-16T20:00'));
  });

  it('tidsatt över midnatt via slutdatum', () => {
    const r = eventInputFrom({ ...base, startTime: '22:00', endTime: '01:00', endDate: '2026-09-17' });
    expect(r.ok && local(r.input.end)).toBe(local('2026-09-17T01:00'));
  });

  it('fel: sluttid före starttid, slutdatum före datum, tom titel', () => {
    expect(eventInputFrom({ ...base, startTime: '12:00', endTime: '11:00' })).toEqual({ ok: false, error: 'Sluttiden måste vara efter starttiden.' });
    expect(eventInputFrom({ ...base, endDate: '2026-09-15' })).toEqual({ ok: false, error: 'Slutdatum måste vara samma dag eller senare.' });
    expect(eventInputFrom({ ...base, title: '  ' })).toEqual({ ok: false, error: 'Ange en titel.' });
  });

  it('plats/anteckningar trimmas, tomma blir null', () => {
    const r = eventInputFrom({ ...base, location: '  Hemma ', notes: '' });
    expect(r.ok && r.input.location).toBe('Hemma');
    expect(r.ok && r.input.notes).toBeNull();
  });
});

describe('eventformulär – fält från befintligt event', () => {
  const ev = (o: Partial<CalendarEvent>): CalendarEvent => ({
    id: 'x', title: 'X', allDay: false, start: '', end: '', location: null, notes: null, createdBy: null, assignee: 'both', isRecurring: false, ...o
  });

  it('heldag en dag → tomt slutdatum, tom tid', () => {
    expect(fieldsFrom(ev({ allDay: true, start: '2026-09-16', end: '2026-09-17' }))).toMatchObject({ date: '2026-09-16', endDate: '', startTime: '', endTime: '' });
  });

  it('heldag flera dagar → inklusivt slutdatum', () => {
    expect(fieldsFrom(ev({ allDay: true, start: '2026-09-16', end: '2026-09-19' })).endDate).toBe('2026-09-18');
  });

  it('tidsatt samma dag → datum + tider, tomt slutdatum', () => {
    const f = fieldsFrom(ev({ start: new Date('2026-09-16T10:00').toISOString(), end: new Date('2026-09-16T11:30').toISOString() }));
    expect(f).toMatchObject({ date: '2026-09-16', endDate: '', startTime: '10:00', endTime: '11:30' });
  });

  it('rundtur: fält → input → fält ger samma sak', () => {
    const f = { ...base, startTime: '09:15', endTime: '10:45', location: 'Gymmet' };
    const r = eventInputFrom(f);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const back = fieldsFrom(ev({ ...r.input, id: 'y', createdBy: null, isRecurring: false, assignee: r.input.assignee ?? 'both' }));
    expect(back).toMatchObject({ title: 'Gym', date: '2026-09-16', endDate: '', startTime: '09:15', endTime: '10:45', location: 'Gymmet' });
  });
});
