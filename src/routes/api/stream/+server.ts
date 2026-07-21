import type { RequestHandler } from './$types';
import { randomUUID } from 'node:crypto';
import { addClient, removeClient } from '$lib/server/sse';

/** SSE-ström (spec §10). Heartbeat var 25 s; klienten identifieras via ?id=. */
export const GET: RequestHandler = ({ url }) => {
  const connId = url.searchParams.get('id') ?? randomUUID();
  const encoder = new TextEncoder();
  let heartbeat: ReturnType<typeof setInterval>;

  const stream = new ReadableStream({
    start(controller) {
      const send = (chunk: string) => controller.enqueue(encoder.encode(chunk));
      addClient(connId, send);
      send(': ansluten\n\n');
      heartbeat = setInterval(() => {
        try {
          send(': ping\n\n');
        } catch {
          clearInterval(heartbeat);
          removeClient(connId);
        }
      }, 25_000);
    },
    cancel() {
      clearInterval(heartbeat);
      removeClient(connId);
    }
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no'
    }
  });
};
