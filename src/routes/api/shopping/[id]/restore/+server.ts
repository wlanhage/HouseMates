import type { RequestHandler } from './$types';
import { tx } from '$lib/server/db';
import { ok, catchHttp, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as shopping from '$lib/server/shopping';

export const POST: RequestHandler = ({ request, params, locals }) => {
  try {
    const result = tx((d) => shopping.restore(d, locals.user!.id, params.id!));
    broadcast('shopping', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
