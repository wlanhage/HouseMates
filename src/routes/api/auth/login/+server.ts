import type { RequestHandler } from './$types';
import { ok, apiError } from '$lib/server/http';
import { verifyLogin, issueSession, loginRateLimited } from '$lib/server/auth';

export const POST: RequestHandler = async ({ request, cookies, getClientAddress }) => {
  if (loginRateLimited(getClientAddress())) {
    return apiError('forbidden', 'För många försök. Vänta en stund och försök igen.', 429);
  }

  let body: { username?: string; password?: string };
  try {
    body = await request.json();
  } catch {
    return apiError('validation', 'Ogiltig begäran.', 400);
  }
  const username = (body.username ?? '').trim();
  const password = body.password ?? '';
  if (!username || !password) {
    return apiError('validation', 'Ange användare och lösenord.', 400);
  }

  const user = await verifyLogin(username, password);
  if (!user) {
    return apiError('unauthorized', 'Fel användare eller lösenord.', 401);
  }

  issueSession(user.id, cookies);
  return ok({ user });
};
