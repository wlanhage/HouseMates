import type { RequestHandler } from './$types';
import { db } from '$lib/server/db';
import { ok } from '$lib/server/http';
import { suggest } from '$lib/server/shopping';

export const GET: RequestHandler = ({ url }) => ok(suggest(db, url.searchParams.get('q') ?? ''));
