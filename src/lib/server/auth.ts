/**
 * Sessioner, login-verifiering och CSRF/rate-limit-hjälpare.
 *
 * - Lösenord verifieras med argon2 (spec §2/§6).
 * - Cookie 'session' = råtoken; i DB lagras endast sha256(token).
 * - last_seen_at uppdateras max 1 ggr/timme.
 */
import * as argon2 from 'argon2';
import { createHash, randomBytes } from 'node:crypto';
import type { Cookies } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { env } from '$env/dynamic/private';
import { db, now } from './db';
import type { User } from '$lib/types';

const SESSION_COOKIE = 'session';
const TTL_DAYS = Number(env.SESSION_TTL_DAYS ?? '180');

const sha256 = (v: string): string => createHash('sha256').update(v).digest('hex');

const selUserById = db.prepare<[string]>(
  'SELECT id, name, color, password_hash FROM users WHERE id = ?'
);
const insSession = db.prepare(
  'INSERT INTO sessions (token_hash, user_id, expires_at, last_seen_at) VALUES (?, ?, ?, ?)'
);
const selSession = db.prepare<[string]>(
  `SELECT s.token_hash, s.expires_at, s.last_seen_at, u.id, u.name, u.color
   FROM sessions s JOIN users u ON u.id = s.user_id
   WHERE s.token_hash = ?`
);
const delSession = db.prepare<[string]>('DELETE FROM sessions WHERE token_hash = ?');
const touchSession = db.prepare<[string, string]>(
  'UPDATE sessions SET last_seen_at = ? WHERE token_hash = ?'
);

type UserRow = User & { password_hash: string };

/** Verifiera användarnamn (= users.id) + lösenord. */
export async function verifyLogin(username: string, password: string): Promise<User | null> {
  const row = selUserById.get(username) as UserRow | undefined;
  if (!row) {
    // Kör en dummy-verify för att jämna ut svarstiden (undvik user-enumeration).
    await argon2.verify('$argon2id$v=19$m=65536,t=3,p=4$xxxxxxxxxxxxxxxxxxxxxx$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx', password).catch(() => false);
    return null;
  }
  const ok = await argon2.verify(row.password_hash, password).catch(() => false);
  if (!ok) return null;
  return { id: row.id, name: row.name, color: row.color };
}

function cookieOpts() {
  return {
    httpOnly: true,
    secure: !dev,
    sameSite: 'lax' as const,
    path: '/',
    maxAge: TTL_DAYS * 24 * 60 * 60
  };
}

/** Skapa session och sätt cookie. */
export function issueSession(userId: string, cookies: Cookies): void {
  const token = randomBytes(32).toString('base64url');
  const expires = new Date(Date.now() + TTL_DAYS * 24 * 60 * 60 * 1000).toISOString();
  insSession.run(sha256(token), userId, expires, now());
  cookies.set(SESSION_COOKIE, token, cookieOpts());
}

/** Slå upp session från råtoken. Uppdaterar last_seen_at max 1 ggr/timme. */
export function lookupSession(rawToken: string | undefined): User | null {
  if (!rawToken) return null;
  const row = selSession.get(sha256(rawToken)) as
    | { token_hash: string; expires_at: string; last_seen_at: string | null; id: string; name: string; color: string }
    | undefined;
  if (!row) return null;
  if (new Date(row.expires_at).getTime() < Date.now()) {
    delSession.run(row.token_hash);
    return null;
  }
  const lastSeen = row.last_seen_at ? new Date(row.last_seen_at).getTime() : 0;
  if (Date.now() - lastSeen > 60 * 60 * 1000) {
    touchSession.run(now(), row.token_hash);
  }
  return { id: row.id, name: row.name, color: row.color };
}

/** Radera session + cookie. */
export function clearSession(rawToken: string | undefined, cookies: Cookies): void {
  if (rawToken) delSession.run(sha256(rawToken));
  cookies.delete(SESSION_COOKIE, { path: '/' });
}

export const sessionCookieName = SESSION_COOKIE;

// ── Rate limit på login: max 10 försök / 15 min per IP (in-memory) ──────────
const attempts = new Map<string, { count: number; resetAt: number }>();
const WINDOW_MS = 15 * 60 * 1000;
const MAX_ATTEMPTS = 10;

/** Returnerar true om IP:t är över gränsen (ska nekas). */
export function loginRateLimited(ip: string): boolean {
  const rec = attempts.get(ip);
  const t = Date.now();
  if (!rec || rec.resetAt < t) {
    attempts.set(ip, { count: 1, resetAt: t + WINDOW_MS });
    return false;
  }
  rec.count += 1;
  return rec.count > MAX_ATTEMPTS;
}
