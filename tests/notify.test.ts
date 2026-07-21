import { describe, it, expect } from 'vitest';
import { inQuietWindow, summarizeActivities, nextQuietTo } from '../src/lib/server/notify-util';

describe('notiser – tysta timmar (spec §15)', () => {
  it('fönster som virar runt midnatt (21:00–07:30)', () => {
    expect(inQuietWindow('22:00', '21:00', '07:30')).toBe(true);
    expect(inQuietWindow('06:00', '21:00', '07:30')).toBe(true);
    expect(inQuietWindow('21:00', '21:00', '07:30')).toBe(true); // inklusiv start
    expect(inQuietWindow('07:30', '21:00', '07:30')).toBe(false); // exklusivt slut
    expect(inQuietWindow('12:00', '21:00', '07:30')).toBe(false);
  });

  it('fönster inom samma dygn (09:00–17:00)', () => {
    expect(inQuietWindow('12:00', '09:00', '17:00')).toBe(true);
    expect(inQuietWindow('08:59', '09:00', '17:00')).toBe(false);
    expect(inQuietWindow('17:00', '09:00', '17:00')).toBe(false);
  });

  it('nextQuietTo ger nästa quiet_to i UTC', () => {
    // 05:00 CEST (< 07:30) → dagens 07:30 CEST = 05:30 UTC
    expect(nextQuietTo(new Date('2026-07-15T03:00:00Z'), '07:30')).toBe('2026-07-15T05:30:00.000Z');
    // 08:00 CEST (> 07:30) → morgondagens 07:30 CEST
    expect(nextQuietTo(new Date('2026-07-15T06:00:00Z'), '07:30')).toBe('2026-07-16T05:30:00.000Z');
  });
});

describe('notiser – digestgruppering (spec §15)', () => {
  it('grupperar per handling med max 3 exempel + räknare', () => {
    const acts = [
      { type: 'shopping.added', payload: { name: 'Mjölk' } },
      { type: 'shopping.added', payload: { name: 'Bröd' } },
      { type: 'shopping.added', payload: { name: 'Kaffe' } },
      { type: 'shopping.added', payload: { name: 'Ägg' } },
      { type: 'todo.done', payload: { title: 'Boka besiktning' } }
    ];
    expect(summarizeActivities(acts)).toBe(
      'la till Mjölk, Bröd, Kaffe + 1 till · bockade av Boka besiktning'
    );
  });

  it('arkivering utan namn ger bara verbet', () => {
    expect(summarizeActivities([{ type: 'shopping.archived', payload: { count: 3 } }])).toBe(
      'tömde avklarade'
    );
  });
});
