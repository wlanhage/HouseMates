import type { RequestHandler } from './$types';
import { db, tx } from '$lib/server/db';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as shopping from '$lib/server/shopping';

export const GET: RequestHandler = () => ok(shopping.listActive(db));

export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const body = await readJson<{ id: string; name: string; qty?: string | null }>(request);
    const result = tx((d) => shopping.add(d, locals.user!.id, body));
    broadcast('shopping', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
