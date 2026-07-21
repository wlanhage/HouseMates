import type { RequestHandler } from './$types';
import { ok, catchHttp, connIdOf } from '$lib/server/http';
import { restoreEvent } from '$lib/server/caldav/write';
import { broadcast } from '$lib/server/sse';

export const POST: RequestHandler = async ({ request, params, locals }) => {
  try {
    const event = await restoreEvent(locals.user!.id, params.id!);
    broadcast('events', connIdOf(request));
    return ok(event);
  } catch (e) {
    return catchHttp(e);
  }
};
