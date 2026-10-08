/**
 * APNs-sändning med token-autentisering (.p8-nyckel). Ren WebCrypto + fetch,
 * så samma fil körs i Deno (edge function) och i vitest (tests/apns.test.ts).
 */

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  privateKey: string; // innehållet i AuthKey_XXXX.p8 (PEM)
  bundleId: string;
  production: boolean;
}

export interface ApnsMessage {
  title: string;
  body: string;
  url: string; // flik i appen: 'inkop' | 'kalender'
}

export interface ApnsResult {
  status: number;
  reason?: string;
  unregistered: boolean;
}

export function apnsPayload(message: ApnsMessage): string {
  return JSON.stringify({
    aps: {
      alert: { title: message.title, body: message.body },
      sound: 'default',
      'thread-id': message.url
    },
    url: message.url
  });
}

// Apple vill att token förnyas högst var 20:e och minst var 60:e minut, annars
// svarar APNs TooManyProviderTokenUpdates. iat avrundas därför till halvtimmen.
const TOKEN_WINDOW_SECONDS = 30 * 60;
let cachedToken: { iat: number; keyId: string; token: string } | null = null;

export async function providerToken(config: ApnsConfig, now = new Date()): Promise<string> {
  const iat = Math.floor(now.getTime() / 1000 / TOKEN_WINDOW_SECONDS) * TOKEN_WINDOW_SECONDS;
  if (cachedToken && cachedToken.iat === iat && cachedToken.keyId === config.keyId) {
    return cachedToken.token;
  }
  const header = base64url(JSON.stringify({ alg: 'ES256', kid: config.keyId }));
  const claims = base64url(JSON.stringify({ iss: config.teamId, iat }));
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToDer(config.privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(`${header}.${claims}`)
  );
  const token = `${header}.${claims}.${base64url(new Uint8Array(signature))}`;
  cachedToken = { iat, keyId: config.keyId, token };
  return token;
}

export async function sendApns(
  config: ApnsConfig,
  deviceToken: string,
  message: ApnsMessage,
  fetchImpl: typeof fetch = fetch
): Promise<ApnsResult> {
  const host = config.production ? 'api.push.apple.com' : 'api.sandbox.push.apple.com';
  const response = await fetchImpl(`https://${host}/3/device/${encodeURIComponent(deviceToken)}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${await providerToken(config)}`,
      'apns-topic': config.bundleId,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json'
    },
    body: apnsPayload(message),
    // Ett Apple som inte svarar får inte hålla kvar resten av körningen.
    signal: AbortSignal.timeout(10_000)
  });
  if (response.ok) return { status: response.status, unregistered: false };
  const reason = ((await response.json().catch(() => ({}))) as { reason?: string }).reason;
  return {
    status: response.status,
    reason,
    unregistered: response.status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered'
  };
}

function pemToDer(pem: string): ArrayBuffer {
  const base64 = pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '');
  const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return bytes.buffer;
}

function base64url(input: string | Uint8Array): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
