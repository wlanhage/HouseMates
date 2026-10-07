/**
 * Receptimport för appen: hämtar en receptsida och läser namn, bild och ingredienser.
 * Sparar ingenting; appen visar resultatet och sparar rätten själv.
 * Hämtningen är samma som i webbappens recipe-import. Genvägsläget behövs inte här,
 * eftersom appen tar emot länkar från Safari via sitt delningstillägg.
 */
// @ts-expect-error npm-import i Deno
import { createClient } from 'npm:@supabase/supabase-js@2';
import {
  parseRecipeHtml,
  parseCoopRecipe,
  coopRecipeId,
  COOP_RECIPE_API,
  type ParsedRecipe
} from '../_shared/recipe.ts';

const MAX_BYTES = 2_000_000;
const TIMEOUT_MS = 10_000;
const UA =
  'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

class HttpError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

/** Bara inloggade får använda funktionen, så att den inte blir en öppen proxy. */
async function requireUser(req: Request): Promise<void> {
  const token = req.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  const service = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data } = await service.auth.getUser(token);
  if (!data?.user) throw new HttpError('Du är inte inloggad.', 401);
}

function validUrl(raw: unknown): string {
  let u: URL;
  try {
    u = new URL(String(raw ?? '').trim());
  } catch {
    throw new HttpError('Ogiltig länk.', 400);
  }
  const host = u.hostname.toLowerCase();
  const privateHost =
    host === 'localhost' ||
    /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|0\.|\[?::1\]?$)/.test(host) ||
    host.endsWith('.local') ||
    host.endsWith('.internal');
  if (!['http:', 'https:'].includes(u.protocol) || privateHost) {
    throw new HttpError('Ogiltig länk.', 400);
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
    if (!res.ok) throw new HttpError(`Sidan svarade ${res.status}.`, 502);
    return (await res.text()).slice(0, MAX_BYTES);
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError('Kunde inte hämta sidan.', 502);
  } finally {
    clearTimeout(timer);
  }
}

/** Sajter som ritar receptet i webbläsaren: hämta datan från deras API när HTML:en saknar ingredienser. */
async function fromSiteApi(url: string, html: string): Promise<ParsedRecipe | null> {
  if (!new URL(url).hostname.endsWith('coop.se')) return null;
  const id = coopRecipeId(html);
  if (!id) return null;
  const res = await fetch(`${COOP_RECIPE_API}${id}?api-version=v1`, {
    headers: { 'User-Agent': UA, Accept: 'application/json' }
  });
  return res.ok ? parseCoopRecipe(await res.json()) : null;
}

/** Bilden som en fullständig https-adress, eller ingen bild alls. */
function imageUrl(raw: string | null, page: string): string | null {
  if (!raw) return null;
  try {
    const u = new URL(raw, page);
    u.protocol = 'https:';
    return u.toString();
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  try {
    await requireUser(req);
    const body = await req.json().catch(() => ({}));
    const url = validUrl(body.url);
    const html = await fetchPage(url);
    let parsed = parseRecipeHtml(html);
    if (parsed.ingredients.length === 0) {
      const fromApi = await fromSiteApi(url, html).catch(() => null);
      if (fromApi) parsed = { ...parsed, ...fromApi, name: fromApi.name ?? parsed.name };
    }
    return json({
      recipe: {
        name: parsed.name ?? new URL(url).hostname,
        items: parsed.ingredients,
        image_url: imageUrl(parsed.imageUrl, url),
        source_url: url
      }
    });
  } catch (e) {
    const error = e instanceof HttpError ? e : new HttpError('Något gick fel.', 500);
    return json({ error: { message: error.message } }, error.status);
  }
});
