import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok } from '$lib/server/http';
import { listActivity } from '$lib/server/activity';

export const GET: RequestHandler = ({ url }) => {
  const limit = Math.min(Number(url.searchParams.get('limit') ?? '30') || 30, 100);
  const beforeRaw = url.searchParams.get('before');
  const before = beforeRaw ? Number(beforeRaw) : undefined;
  return ok(listActivity(db, limit, before));
};
