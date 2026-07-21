import { describe, it, expect } from 'vitest';
import { replayOne, type Mutation } from '../src/lib/client/outbox';
import { ApiError } from '../src/lib/client/api';

const m: Mutation = { method: 'POST', path: '/api/shopping', body: { id: 'x' }, entity: 'shopping' };

describe('outbox – replay-beslutslogik (spec §12.3)', () => {
  it('lyckat skick → sent', async () => {
    const outcome = await replayOne(m, async () => ({ ok: true }));
    expect(outcome).toBe('sent');
  });

  it('nätverksfel → stop (fortfarande offline, behåll i kön)', async () => {
    const outcome = await replayOne(m, async () => {
      throw new ApiError('network', 'Nätverksfel.', 0);
    });
    expect(outcome).toBe('stop');
  });

  it('version_conflict → dropped (server vinner)', async () => {
    const outcome = await replayOne(m, async () => {
      throw new ApiError('version_conflict', 'konflikt', 409, {});
    });
    expect(outcome).toBe('dropped');
  });

  it('duplicate → dropped (server vinner)', async () => {
    const outcome = await replayOne(m, async () => {
      throw new ApiError('duplicate', 'finns', 409, {});
    });
    expect(outcome).toBe('dropped');
  });

  it('idempotent POST som redan finns (200) → sent, ingen dubblett', async () => {
    // Servern svarar 200 med befintlig resurs vid replay av samma klient-id.
    let calls = 0;
    const send = async () => {
      calls++;
      return { item: { id: 'x' }, merged: false };
    };
    expect(await replayOne(m, send)).toBe('sent');
    expect(await replayOne(m, send)).toBe('sent'); // dubbelreplay ofarlig
    expect(calls).toBe(2);
  });
});
