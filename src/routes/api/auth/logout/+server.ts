import type { RequestHandler } from './$types';
import { ok } from '$lib/server/http';
import { clearSession, sessionCookieName } from '$lib/server/auth';

export const POST: RequestHandler = async ({ cookies }) => {
  clearSession(cookies.get(sessionCookieName), cookies);
  return ok({ ok: true });
};
