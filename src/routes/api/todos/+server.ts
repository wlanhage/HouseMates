import type { RequestHandler } from './$types';
import { db, tx } from '$lib/server/db';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { broadcast } from '$lib/server/sse';
import * as todos from '$lib/server/todos';

export const GET: RequestHandler = ({ url }) => {
  const filter = url.searchParams.get('filter') === 'done' ? 'done' : 'open';
  return ok(filter === 'done' ? todos.listDone(db) : todos.listOpen(db));
};

export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const body = await readJson<{
      id: string;
      title: string;
      notes?: string | null;
      assignee?: string | null;
      due_date?: string | null;
    }>(request);
    const result = tx((d) => todos.add(d, locals.user!.id, body));
    broadcast('todos', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
