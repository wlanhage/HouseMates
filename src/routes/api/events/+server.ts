import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok, apiError, catchHttp, readJson, connIdOf } from '$lib/server/http';
import { HttpError } from '$lib/server/http';
import { listEvents } from '$lib/server/events';
import { createEvent } from '$lib/server/caldav/write';
import { broadcast } from '$lib/server/sse';

const DATE = /^\d{4}-\d{2}-\d{2}$/;

export const GET: RequestHandler = ({ url }) => {
  const from = url.searchParams.get('from') ?? '';
  const to = url.searchParams.get('to') ?? '';
  if (!DATE.test(from) || !DATE.test(to)) {
    return apiError('validation', 'from/to måste vara YYYY-MM-DD.', 400);
  }
  return ok(listEvents(db, from, to));
};

interface EventBody {
  title?: string;
  allDay?: boolean;
  start?: string;
  end?: string;
  location?: string | null;
  notes?: string | null;
}

function validate(b: EventBody): Required<Pick<EventBody, 'title' | 'allDay' | 'start' | 'end'>> & {
  location: string | null;
  notes: string | null;
} {
  const title = (b.title ?? '').trim();
  if (!title) throw new HttpError('validation', 'Titel krävs.', 400);
  const allDay = !!b.allDay;
  const start = b.start ?? '';
  const end = b.end ?? '';
  if (allDay) {
    if (!DATE.test(start) || !DATE.test(end)) {
      throw new HttpError('validation', 'Heldag kräver rena datum.', 400);
    }
    if (end <= start) throw new HttpError('validation', 'Slut måste vara efter start.', 400);
  } else {
    const s = Date.parse(start);
    const e = Date.parse(end);
    if (Number.isNaN(s) || Number.isNaN(e)) {
      throw new HttpError('validation', 'Ogiltiga tider.', 400);
    }
    if (e <= s) throw new HttpError('validation', 'Slut måste vara efter start.', 400);
  }
  return { title, allDay, start, end, location: b.location ?? null, notes: b.notes ?? null };
}

export const POST: RequestHandler = async ({ request, locals }) => {
  try {
    const body = await readJson<EventBody>(request);
    const fields = validate(body);
    const event = await createEvent(locals.user!.id, fields);
    broadcast('events', connIdOf(request));
    return ok(event);
  } catch (e) {
    return catchHttp(e);
  }
};
