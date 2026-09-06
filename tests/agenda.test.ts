import { describe, it, expect } from 'vitest';
import { buildAgenda } from '../src/lib/client/agenda';
import type { CalendarEvent } from '../src/lib/types';

const ev = (o: Partial<CalendarEvent>): CalendarEvent => ({
  id: 'x',
  title: 'X',
  allDay: false,
  start: '',
  end: '',
  location: null,
  createdBy: null,
  assignee: 'both',
  isRecurring: false,
  ...o
});

describe('agenda – gruppering per dag (spec §12.2)', () => {
  it('flerdagars heldag visas under varje dag med rätt "dag X av Y"', () => {
    const evs = [ev({ id: 'sem', title: 'Semester', allDay: true, start: '2026-07-01', end: '2026-07-04' })];
    const days = buildAgenda(evs, '2026-07-01', '2026-07-05');
    expect(days.map((d) => d.date)).toEqual(['2026-07-01', '2026-07-02', '2026-07-03']); // end exkl.
    expect(days[0].entries[0]).toMatchObject({ dayIndex: 1, dayCount: 3, multiDay: true });
    expect(days[1].entries[0]).toMatchObject({ dayIndex: 2, dayCount: 3 });
    expect(days[2].entries[0]).toMatchObject({ dayIndex: 3, dayCount: 3 });
  });

  it('heldag sorteras före tidsatt samma dag', () => {
    const evs = [
      ev({ id: 't', title: 'Möte', start: '2026-07-15T12:00:00.000Z', end: '2026-07-15T13:00:00.000Z' }),
      ev({ id: 'a', title: 'Röd dag', allDay: true, start: '2026-07-15', end: '2026-07-16' })
    ];
    const [day] = buildAgenda(evs, '2026-07-15', '2026-07-15');
    expect(day.entries.map((e) => e.event.id)).toEqual(['a', 't']);
  });

  it('tomma dagar utelämnas', () => {
    const evs = [ev({ id: 'a', allDay: true, start: '2026-07-15', end: '2026-07-16' })];
    const days = buildAgenda(evs, '2026-07-10', '2026-07-20');
    expect(days).toHaveLength(1);
    expect(days[0].date).toBe('2026-07-15');
  });
});
