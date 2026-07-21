/**
 * Kör på varje request:
 *  - slår upp sessionen → locals.user
 *  - CSRF: mutationer mot /api kräver header X-Requested-With: fetch
 *  - skyddar /api/* (utom login) → 401 om ej inloggad
 *  - sätter säkerhetsheaders (spec §14)
 *
 * Bakgrundsjobben startas en gång här (spec §13); de registreras
 * milstolpe för milstolpe i $lib/server/jobs.ts.
 */
import type { Handle } from '@sveltejs/kit';
import { dev } from '$app/environment';
import { lookupSession, sessionCookieName } from '$lib/server/auth';
import { apiError } from '$lib/server/http';
import { startBackgroundJobs } from '$lib/server/jobs';

startBackgroundJobs();

const MUTATING = new Set(['POST', 'PATCH', 'PUT', 'DELETE']);

export const handle: Handle = async ({ event, resolve }) => {
  const { url, request } = event;

  // 1. Session → locals.user
  event.locals.user = lookupSession(event.cookies.get(sessionCookieName));

  const isApi = url.pathname.startsWith('/api/');
  const isLogin = url.pathname === '/api/auth/login';

  if (isApi) {
    // 2. CSRF – enkel headercheck + SameSite=Lax räcker för v1 (spec §6).
    if (MUTATING.has(request.method) && request.headers.get('x-requested-with') !== 'fetch') {
      return apiError('forbidden', 'Saknar X-Requested-With.', 403);
    }
    // 3. Auth-guard för alla API utom login.
    if (!isLogin && !event.locals.user) {
      return apiError('unauthorized', 'Inte inloggad.', 401);
    }
  }

  const response = await resolve(event);

  // 4. Säkerhetsheaders
  response.headers.set('X-Content-Type-Options', 'nosniff');
  response.headers.set('Referrer-Policy', 'same-origin');
  if (!dev) {
    response.headers.set(
      'Content-Security-Policy',
      [
        "default-src 'self'",
        "img-src 'self' data:",
        "style-src 'self' 'unsafe-inline'",
        "connect-src 'self'",
        "worker-src 'self'",
        "manifest-src 'self'",
        "base-uri 'self'",
        "form-action 'self'"
      ].join('; ')
    );
  }
  return response;
};
