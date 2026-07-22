/**
 * Genererar VAPID-nycklar för web push i formatet edge-funktionen behöver.
 *   node deploy/gen-vapid.mjs
 * Skriver ut:
 *   VAPID_KEYS_JSON   – sätts som Supabase-secret (supabase secrets set)
 *   PUBLIC_VAPID_KEY  – läggs i .env (byggs in i frontend)
 */
import { webcrypto as crypto } from 'node:crypto';

const pair = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
  'sign',
  'verify'
]);
const publicJwk = await crypto.subtle.exportKey('jwk', pair.publicKey);
const privateJwk = await crypto.subtle.exportKey('jwk', pair.privateKey);

// applicationServerKey = okomprimerad P-256-punkt, base64url
const raw = new Uint8Array(await crypto.subtle.exportKey('raw', pair.publicKey));
const b64url = Buffer.from(raw).toString('base64url');

console.log('VAPID_KEYS_JSON=' + JSON.stringify({ publicKey: publicJwk, privateKey: privateJwk }));
console.log('PUBLIC_VAPID_KEY=' + b64url);
