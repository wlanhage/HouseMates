import { describe, it, expect } from 'vitest';
import { choreDueDate, intervalLabel, splitInterval, intervalDays } from '../src/lib/client/chores';

const localIso = (s: string) => new Date(s).toISOString();

describe('städsysslor – sista dag', () => {
  it('utan intervall finns ingen sista dag', () => {
    expect(choreDueDate({ interval_days: null, last_done_at: null, created_at: localIso('2026-09-01T10:00') })).toBeNull();
  });

  it('räknas från när den faktiskt gjordes: gjord 2 sep, varje vecka → 9 sep', () => {
    expect(
      choreDueDate({ interval_days: 7, last_done_at: localIso('2026-09-02T18:30'), created_at: localIso('2026-08-01T10:00') })
    ).toBe('2026-09-09');
  });

  it('aldrig gjord → från när den skapades', () => {
    expect(choreDueDate({ interval_days: 21, last_done_at: null, created_at: localIso('2026-09-01T10:00') })).toBe('2026-09-22');
  });
});

describe('städsysslor – intervall', () => {
  it('etiketter', () => {
    expect(intervalLabel(7)).toBe('varje vecka');
    expect(intervalLabel(14)).toBe('varannan vecka');
    expect(intervalLabel(21)).toBe('var 3:e vecka');
    expect(intervalLabel(1)).toBe('varje dag');
    expect(intervalLabel(2)).toBe('varannan dag');
    expect(intervalLabel(10)).toBe('var 10:e dag');
    expect(intervalLabel(22)).toBe('var 22:a dag');
    expect(intervalLabel(11)).toBe('var 11:e dag');
  });

  it('dagar ↔ antal + enhet', () => {
    expect(splitInterval(21)).toEqual({ count: '3', unit: 'veckor' });
    expect(splitInterval(10)).toEqual({ count: '10', unit: 'dagar' });
    expect(splitInterval(null)).toEqual({ count: '', unit: 'veckor' });
    expect(intervalDays('3', 'veckor')).toBe(21);
    expect(intervalDays('10', 'dagar')).toBe(10);
    expect(intervalDays('', 'veckor')).toBeNull();
    expect(intervalDays('0', 'dagar')).toBeNull();
  });
});
