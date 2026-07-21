/**
 * fetch-wrapper: sätter alltid CSRF-headern X-Requested-With: fetch och
 * JSON-headers, och normaliserar felformatet från spec §7.1.
 *
 * Outbox-integration (offline-kö) läggs till i M3.
 */
import type { ApiErrorCode } from '$lib/types';
import { connId } from './conn';

export class ApiError extends Error {
  constructor(
    public code: ApiErrorCode | 'network' | 'unknown',
    message: string,
    public status: number,
    public extra: Record<string, unknown> = {}
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

type Method = 'GET' | 'POST' | 'PATCH' | 'PUT' | 'DELETE';

async function request<T>(method: Method, path: string, body?: unknown): Promise<T> {
  let res: Response;
  try {
    res = await fetch(path, {
      method,
      headers: {
        'X-Requested-With': 'fetch',
        'X-Conn-Id': connId,
        ...(body !== undefined ? { 'Content-Type': 'application/json' } : {})
      },
      body: body !== undefined ? JSON.stringify(body) : undefined
    });
  } catch {
    throw new ApiError('network', 'Nätverksfel.', 0);
  }

  if (res.status === 204) return null as T;

  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const err = (data && data.error) || {};
    throw new ApiError(err.code ?? 'unknown', err.message ?? 'Något gick fel.', res.status, err);
  }
  return data as T;
}

export const apiGet = <T>(path: string): Promise<T> => request<T>('GET', path);
export const apiPost = <T>(path: string, body?: unknown): Promise<T> => request<T>('POST', path, body);
export const apiPatch = <T>(path: string, body?: unknown): Promise<T> => request<T>('PATCH', path, body);
export const apiDelete = <T>(path: string, body?: unknown): Promise<T> => request<T>('DELETE', path, body);
