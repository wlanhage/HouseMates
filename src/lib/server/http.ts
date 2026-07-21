/** Små hjälpare för JSON-svar och felformat enligt spec §7.1.
 *  Använder web-standard Response (ingen SvelteKit-import) så tjänstelagret
 *  kan importeras i tester utan ramverket. */
import type { ApiErrorCode } from '$lib/types';

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

export function ok<T>(data: T, status = 200): Response {
  return jsonResponse(data, status);
}

export function apiError(
  code: ApiErrorCode | 'server',
  message: string,
  status: number,
  extra: Record<string, unknown> = {}
): Response {
  return jsonResponse({ error: { code, message, ...extra } }, status);
}

/** Fånga fel i en endpoint: HttpError → rätt svar, annat → 500. */
export function catchHttp(e: unknown): Response {
  if (e instanceof HttpError) return e.toResponse();
  console.error('[api] oväntat fel:', e);
  return apiError('server', 'Ett oväntat fel inträffade.', 500);
}

/** Kastbart fel som API-routes kan slänga och som mappas till rätt svar. */
export class HttpError extends Error {
  constructor(
    public code: ApiErrorCode,
    message: string,
    public status: number,
    public extra: Record<string, unknown> = {}
  ) {
    super(message);
    this.name = 'HttpError';
  }
  toResponse(): Response {
    return apiError(this.code, this.message, this.status, this.extra);
  }
}

/** Läs JSON-body eller kasta 400. */
export async function readJson<T>(request: Request): Promise<T> {
  try {
    return (await request.json()) as T;
  } catch {
    throw new HttpError('validation', 'Ogiltig JSON.', 400);
  }
}

/** Klientens SSE-connection-id (så broadcast hoppar över avsändaren). */
export const connIdOf = (request: Request): string | undefined =>
  request.headers.get('x-conn-id') ?? undefined;
