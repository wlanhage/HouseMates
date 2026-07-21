import type { RequestHandler } from './$types';
import { ok, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { updateEvent, deleteEvent } from '$lib/server/caldav/write';
import { broadcast } from '$lib/server/sse';

export const PATCH: RequestHandler = async ({ request, params, locals }) => {
  try {
    const body = await readJson<{
      title?: string;
      allDay?: boolean;
      start?: string;
      end?: string;
      location?: string | null;
      notes?: string | null;
    }>(request);
    const event = await updateEvent(locals.user!.id, params.id!, body);
    broadcast('events', connIdOf(request));
    return ok(event);
  } catch (e) {
    return catchHttp(e);
  }
};

export const DELETE: RequestHandler = async ({ request, params, locals }) => {
  try {
    const result = await deleteEvent(locals.user!.id, params.id!);
    broadcast('events', connIdOf(request));
    return ok(result);
  } catch (e) {
    return catchHttp(e);
  }
};
