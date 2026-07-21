import type { RequestHandler } from './$types';
import { tx } from '$lib/server/db';
import { ok, catchHttp, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as todos from '$lib/server/todos';

export const POST: RequestHandler = ({ request, params, locals }) => {
  try {
    const result = tx((d) => todos.restore(d, locals.user!.id, params.id!));
    broadcast('todos', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
