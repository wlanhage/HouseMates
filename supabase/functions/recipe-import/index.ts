/**
 * Receptimport: hämtar en receptsida och läser namn, bild och ingredienser.
 *
 * Två anropare:
 *  - Appen (inloggad medlem): { url } → { recipe } utan att spara; användaren
 *    granskar och sparar i formuläret.
 *  - iPhone-genvägen (header x-import-token): { url } → sparar favoriten
 *    direkt och svarar ALLTID 200 med ren text ("Sparad: …"), även vid fel,
 *    så genvägen kan visa svaret rakt av i en notis utan extra steg.
 */
import {
  serviceClient,
  jsonResponse,
  handleOptions,
  requireMember,
  corsHeaders,
  HttpError
} from '../_shared/util.ts';
import { parseRecipeHtml } from '../_shared/recipe.ts';

const MAX_BYTES = 2_000_000;
const TIMEOUT_MS = 10_000;
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

function validUrl(raw: unknown): string {
  let u: URL;
  try {
    u = new URL(String(raw ?? '').trim());
  } catch {
    throw new HttpError('validation', 'Ogiltig länk.', 400);
  }
  const host = u.hostname.toLowerCase();
  const privateHost =
    host === 'localhost' ||
    /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.|\[?::1\]?$)/.test(host) ||
    host.endsWith('.local') ||
    host.endsWith('.internal');
  if (!['http:', 'https:'].includes(u.protocol) || privateHost) {
    throw new HttpError('validation', 'Ogiltig länk.', 400);
  }
  return u.toString();
}

async function fetchPage(url: string): Promise<string> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': UA, Accept: 'text/html,application/xhtml+xml,*/*' },
      redirect: 'follow',
      signal: ctrl.signal
    });
    if (!res.ok) throw new HttpError('fetch_failed', `Sidan svarade ${res.status}.`, 502);
    return (await res.text()).slice(0, MAX_BYTES);
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError('fetch_failed', 'Kunde inte hämta sidan.', 502);
  } finally {
    clearTimeout(timer);
  }
}

/** Genvägens svar: ren text som visas direkt i notisen. Loggas för felsökning (aldrig nyckeln). */
function textResponse(message: string, url = ''): Response {
  console.log(`genväg: ${url ? new URL(url).hostname : '-'} → ${message}`);
  return new Response(message, {
    status: 200,
    headers: { ...corsHeaders, 'Content-Type': 'text/plain; charset=utf-8' }
  });
}

async function userFromToken(
  svc: ReturnType<typeof serviceClient>,
  token: string
): Promise<string | null> {
  const { data } = await svc.from('import_tokens').select('username').eq('token', token).maybeSingle();
  return (data?.username as string | undefined) ?? null;
}

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  // Genvägen kan skicka nyckel + länk som query (GET …?key=…&url=…) istället
  // för header + JSON – färre steg att konfigurera i Genvägar.
  const query = new URL(req.url).searchParams;
  const token = req.headers.get('x-import-token') ?? query.get('key');
  const viaShortcut = !!token;
  let body: { url?: unknown } = {};
  try {
    const svc = serviceClient();
    let me: string;
    if (viaShortcut) {
      const owner = await userFromToken(svc, token);
      if (!owner) throw new HttpError('unauthorized', 'Fel nyckel – kopiera den från Inställningar igen.', 401);
      me = owner;
    } else {
      me = await requireMember(req);
    }

    body = req.method === 'GET' ? { url: query.get('url') } : await req.json().catch(() => ({}));
    const url = validUrl(body.url);
    const parsed = parseRecipeHtml(await fetchPage(url));
    const recipe = {
      name: parsed.name ?? new URL(url).hostname,
      items: parsed.ingredients,
      image_url: parsed.imageUrl,
      source_url: url
    };
    if (!viaShortcut) return jsonResponse({ recipe });

    // Samma länk två gånger → befintlig favorit, ingen dubblett.
    const { data: existing } = await svc
      .from('favorites')
      .select('id, name, items')
      .eq('source_url', url)
      .is('deleted_at', null)
      .maybeSingle();
    if (existing) return textResponse(`Fanns redan: ${existing.name}`, url);

    const { error } = await svc
      .from('favorites')
      .insert({ id: crypto.randomUUID(), ...recipe, created_by: me });
    if (error) throw new HttpError('db', 'Kunde inte spara favoriten.', 500);

    const n = recipe.items.length;
    const message =
      n > 0
        ? `Sparad: ${recipe.name} (${n === 1 ? '1 vara' : `${n} varor`})`
        : `Sparad: ${recipe.name} – inga ingredienser hittades, fyll i dem i appen`;
    return textResponse(message, url);
  } catch (e) {
    const err = e instanceof HttpError ? e : new HttpError('error', 'Något gick fel.', 500);
    if (viaShortcut) return textResponse(err.message, typeof body?.url === 'string' && /^https?:\/\//.test(body.url) ? body.url : '');
    return err.response();
  }
});
