/**
 * AES-256-GCM för CalDAV-credentials i vila (spec §14).
 * Format på lagrad blob: [12 byte IV][16 byte authtag][ciphertext].
 * Nyckel via APP_ENCRYPTION_KEY (32 byte base64).
 */
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { env } from '$env/dynamic/private';

function key(): Buffer {
  const k = Buffer.from(env.APP_ENCRYPTION_KEY ?? '', 'base64');
  if (k.length !== 32) {
    throw new Error('APP_ENCRYPTION_KEY måste vara 32 byte (base64).');
  }
  return k;
}

export function encrypt(plaintext: string): Buffer {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key(), iv);
  const ct = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, ct]);
}

export function decrypt(blob: Buffer): string {
  const iv = blob.subarray(0, 12);
  const tag = blob.subarray(12, 28);
  const ct = blob.subarray(28);
  const decipher = createDecipheriv('aes-256-gcm', key(), iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
}
