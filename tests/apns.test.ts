import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import {
  apnsPayload,
  providerToken,
  sendApns,
  type ApnsConfig
} from '../native/supabase/functions/_shared/apns';

async function testKey(keyId: string): Promise<{ config: ApnsConfig; publicKey: CryptoKey }> {
  const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const der = Buffer.from(await crypto.subtle.exportKey('pkcs8', pair.privateKey)).toString('base64');
  const config: ApnsConfig = {
    keyId,
    teamId: 'TEAM42',
    privateKey: `-----BEGIN PRIVATE KEY-----\n${der}\n-----END PRIVATE KEY-----`,
    bundleId: 'se.housemates.app',
    production: false
  };
  return { config, publicKey: pair.publicKey };
}

const decode = (part: string) => JSON.parse(Buffer.from(part, 'base64url').toString());

describe('APNs-token – ES256-JWT signerad med .p8-nyckeln', () => {
  it('har rätt header och claims och en giltig signatur', async () => {
    const { config, publicKey } = await testKey('KEY1');
    const token = await providerToken(config, new Date('2026-10-05T10:14:00Z'));
    const [header, claims, signature] = token.split('.');

    expect(decode(header)).toEqual({ alg: 'ES256', kid: 'KEY1' });
    expect(decode(claims)).toEqual({ iss: 'TEAM42', iat: Date.parse('2026-10-05T10:00:00Z') / 1000 });
    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: 'SHA-256' },
      publicKey,
      Buffer.from(signature, 'base64url'),
      new TextEncoder().encode(`${header}.${claims}`)
    );
    expect(valid).toBe(true);
  });

  it('återanvänds inom halvtimmen och förnyas i nästa (APNs stryper täta förnyelser)', async () => {
    const { config } = await testKey('KEY2');
    const first = await providerToken(config, new Date('2026-10-05T10:31:00Z'));
    const sameWindow = await providerToken(config, new Date('2026-10-05T10:59:00Z'));
    const nextWindow = await providerToken(config, new Date('2026-10-05T11:01:00Z'));

    expect(sameWindow).toBe(first);
    expect(nextWindow).not.toBe(first);
  });
});

describe('APNs-förfrågan', () => {
  it('skickar notisen till sandlådan med rätt ämne och flik', async () => {
    const { config } = await testKey('KEY3');
    const calls: { url: string; init: RequestInit }[] = [];
    const fakeFetch = (async (url: string, init: RequestInit) => {
      calls.push({ url, init });
      return new Response(null, { status: 200 });
    }) as typeof fetch;

    const result = await sendApns(config, 'abc123', { title: 'Anna la till Mjölk på listan', body: '', url: 'inkop' }, fakeFetch);

    expect(result).toEqual({ status: 200, unregistered: false });
    expect(calls[0].url).toBe('https://api.sandbox.push.apple.com/3/device/abc123');
    const headers = calls[0].init.headers as Record<string, string>;
    expect(headers['apns-topic']).toBe('se.housemates.app');
    expect(headers['apns-push-type']).toBe('alert');
    expect(headers.authorization).toMatch(/^bearer [\w-]+\.[\w-]+\.[\w-]+$/);
    expect(JSON.parse(calls[0].init.body as string)).toEqual({
      aps: { alert: { title: 'Anna la till Mjölk på listan', body: '' }, sound: 'default', 'thread-id': 'inkop' },
      url: 'inkop'
    });
  });

  it('markerar token som ogiltig vid 410 och BadDeviceToken, inte vid andra fel', async () => {
    const { config } = await testKey('KEY4');
    const replyWith = (status: number, reason: string) =>
      (async () => new Response(JSON.stringify({ reason }), { status })) as unknown as typeof fetch;
    const message = { title: 't', body: 'b', url: 'kalender' };

    expect(await sendApns(config, 'x', message, replyWith(410, 'Unregistered'))).toEqual({ status: 410, reason: 'Unregistered', unregistered: true });
    expect((await sendApns(config, 'x', message, replyWith(400, 'BadDeviceToken'))).unregistered).toBe(true);
    expect((await sendApns(config, 'x', message, replyWith(429, 'TooManyRequests'))).unregistered).toBe(false);
  });

  it('payload bär fliken så att ett tryck öppnar rätt vy', () => {
    expect(JSON.parse(apnsPayload({ title: 'T', body: 'B', url: 'kalender' })).url).toBe('kalender');
  });
});

describe('digest-spegeln i native', () => {
  it('är identisk med webbappens digest.ts', () => {
    const original = readFileSync('supabase/functions/_shared/digest.ts', 'utf8');
    const mirror = readFileSync('native/supabase/functions/_shared/digest.ts', 'utf8');
    expect(mirror).toBe(original);
  });
});
