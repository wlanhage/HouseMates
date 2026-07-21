import type { RequestHandler } from './$types';
import { tx } from '$lib/server/db';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as todos from '$lib/server/todos';

export const PATCH: RequestHandler = async ({ request, params, locals }) => {
  try {
    const body = await readJson<{
      version: number;
      done?: boolean;
      title?: string;
      notes?: string | null;
      assignee?: string | null;
      due_date?: string | null;
    }>(request);
    const result = tx((d) => todos.patch(d, locals.user!.id, params.id!, body));
    broadcast('todos', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};

export const DELETE: RequestHandler = ({ request, params, locals }) => {
  try {
    const result = tx((d) => todos.remove(d, locals.user!.id, params.id!));
    broadcast('todos', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
