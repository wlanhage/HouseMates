import { describe, it, expect } from 'vitest';
import { buildMonth, addMonths, monthOf, WEEKDAYS } from '../src/lib/client/monthGrid';

describe('månadsrutnät – veckan börjar på måndag', () => {
  it('september 2026 börjar på en tisdag → en utfyllnadscell, 30 dagar', () => {
    const m = buildMonth(2026, 9);
    expect(m.label).toBe('September 2026');
    expect(m.first).toBe('2026-09-01');
    expect(m.last).toBe('2026-09-30');
    expect(m.cells[0]).toEqual({ date: null, day: 0 });
    expect(m.cells[1]).toEqual({ date: '2026-09-01', day: 1 });
    expect(m.cells.length).toBe(31);
    expect(m.cells[m.cells.length - 1].date).toBe('2026-09-30');
  });

  it('februari 2026 börjar på en söndag → sex utfyllnadsceller, 28 dagar', () => {
    const m = buildMonth(2026, 2);
    expect(m.cells.filter((c) => c.date === null).length).toBe(6);
    expect(m.cells.filter((c) => c.date).length).toBe(28);
  });

  it('addMonths rullar över årsskiftet åt båda håll', () => {
    expect(addMonths(2026, 12, 1)).toEqual({ year: 2027, month: 1 });
    expect(addMonths(2026, 1, -1)).toEqual({ year: 2025, month: 12 });
    expect(addMonths(2026, 9, 5)).toEqual({ year: 2027, month: 2 });
  });

  it('monthOf läser år och månad ur ett datum', () => {
    expect(monthOf('2026-09-07')).toEqual({ year: 2026, month: 9 });
  });

  it('veckodagarna är sju och börjar på måndag', () => {
    expect(WEEKDAYS).toHaveLength(7);
    expect(WEEKDAYS[0]).toBe('mån');
    expect(WEEKDAYS[6]).toBe('sön');
  });
});
