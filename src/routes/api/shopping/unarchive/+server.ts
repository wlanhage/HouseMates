import type { RequestHandler } from './$types';
import { tx } from '$lib/server/db';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as shopping from '$lib/server/shopping';

export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const body = await readJson<{ ids: string[] }>(request);
    const result = tx((d) => shopping.unarchive(d, locals.user!.id, body.ids ?? []));
    broadcast('shopping', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
