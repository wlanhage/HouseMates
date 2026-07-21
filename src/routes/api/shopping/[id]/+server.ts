import type { RequestHandler } from './$types';
import { tx } from '$lib/server/db';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as shopping from '$lib/server/shopping';

export const PATCH: RequestHandler = async ({ request, params, locals }) => {
  try {
    const body = await readJson<{
      version: number;
      checked?: boolean;
      name?: string;
      qty?: string | null;
    }>(request);
    const result = tx((d) => shopping.patch(d, locals.user!.id, params.id!, body));
    broadcast('shopping', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};

export const DELETE: RequestHandler = ({ request, params, locals }) => {
  try {
    const result = tx((d) => shopping.remove(d, locals.user!.id, params.id!));
    broadcast('shopping', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
