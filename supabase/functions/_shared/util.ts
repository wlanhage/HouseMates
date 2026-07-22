/** Delade hjälpare för edge functions: klienter, auth och AES-GCM. */
// @ts-expect-error npm-import i Deno
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

const URL = Deno.env.get('SUPABASE_URL')!;
const ANON = Deno.env.get('SUPABASE_ANON_KEY')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/** Klient med full åtkomst (förbi RLS) – används för cache/logg/kö. */
export function serviceClient(): SupabaseClient {
  return createClient(URL, SERVICE, { auth: { persistSession: false } });
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders }
  });
}

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

export function handleOptions(req: Request): Response | null {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  return null;
}

export class HttpError extends Error {
  constructor(
    public code: string,
    message: string,
    public status: number,
    public extra: Record<string, unknown> = {}
  ) {
    super(message);
  }
  response(): Response {
    return jsonResponse({ error: { code: this.code, message: this.message, ...this.extra } }, this.status);
  }
}

/** Är anropet gjort av systemet (cron/service) snarare än en användare? */
export function isServiceCall(req: Request): boolean {
  const auth = req.headers.get('Authorization') ?? '';
  if (auth === `Bearer ${SERVICE}`) return true;
  // Egen delad hemlighet – oberoende av API-nyckelformat (legacy/ny)
  const cronSecret = Deno.env.get('CRON_SECRET');
  return !!cronSecret && req.headers.get('x-cron-secret') === cronSecret;
}

/** Kräv inloggad medlem; returnerar username. */
export async function requireMember(req: Request): Promise<string> {
  const authHeader = req.headers.get('Authorization') ?? '';
  const supa = createClient(URL, ANON, {
    auth: { persistSession: false },
    global: { headers: { Authorization: authHeader } }
  });
  const { data, error } = await supa.auth.getUser();
  if (error || !data.user) throw new HttpError('unauthorized', 'Inte inloggad.', 401);
  const svc = serviceClient();
  const { data: prof } = await svc
    .from('profiles')
    .select('username')
    .eq('id', data.user.id)
    .maybeSingle();
  if (!prof) throw new HttpError('forbidden', 'Inte medlem.', 403);
  return prof.username as string;
}

// ── AES-256-GCM (WebCrypto) för CalDAV-lösenord i vila ───────
const b64ToBytes = (b64: string): Uint8Array =>
  Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const bytesToB64 = (b: Uint8Array): string => btoa(String.fromCharCode(...b));

async function encKey(): Promise<CryptoKey> {
  const raw = b64ToBytes(Deno.env.get('CALDAV_ENC_KEY') ?? '');
  if (raw.length !== 32) throw new Error('CALDAV_ENC_KEY måste vara 32 byte base64');
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt', 'decrypt']);
}

export async function encryptSecret(plaintext: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await encKey();
  const ct = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, new TextEncoder().encode(plaintext))
  );
  const out = new Uint8Array(iv.length + ct.length);
  out.set(iv);
  out.set(ct, iv.length);
  return bytesToB64(out);
}

export async function decryptSecret(blobB64: string): Promise<string> {
  const blob = b64ToBytes(blobB64);
  const iv = blob.slice(0, 12);
  const ct = blob.slice(12);
  const key = await encKey();
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, ct);
  return new TextDecoder().decode(pt);
}

/** Sanera hemligheter ur felmeddelanden innan de sparas. */
export function sanitize(err: unknown, secret: string): string {
  let msg = err instanceof Error ? err.message : String(err);
  if (secret) msg = msg.split(secret).join('***');
  return msg.slice(0, 300);
}
