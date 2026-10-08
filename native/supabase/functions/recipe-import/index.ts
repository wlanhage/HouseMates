/**
 * Receptimport för appen: hämtar en receptsida och läser namn, bild och ingredienser.
 * Sparar ingenting; appen visar resultatet och sparar rätten själv.
 * Tolkningen är samma som i webbappens recipe-import. Genvägsläget behövs inte här,
 * eftersom appen tar emot länkar från Safari via sitt delningstillägg.
 *
 * Funktionen hämtar adresser som användaren skickar, så den får aldrig nå servrar i det egna
 * nätet: varje adress, också efter en omdirigering, slås upp och kontrolleras före hämtningen.
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
const MAX_REDIRECTS = 5;
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

/** Bara medlemmar i ett hushåll får använda funktionen, så att den inte blir en öppen proxy. */
async function requireMember(req: Request): Promise<void> {
  const token = req.headers.get('Authorization')?.replace(/^Bearer /, '') ?? '';
  const service = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const { data } = await service.auth.getUser(token);
  if (!data?.user) throw new HttpError('Du är inte inloggad.', 401);
  const { count } = await service
    .from('household_members')
    .select('user_id', { count: 'exact', head: true })
    .eq('user_id', data.user.id);
  if (!count) throw new HttpError('Du är inte med i något hushåll.', 403);
}

// Lokala och reserverade IPv4-nät, också delade (100.64/10), test (198.18/15) och multicast (224+).
const PRIVATE_IPV4 =
  /^(0|10|127)\.|^169\.254\.|^192\.168\.|^172\.(1[6-9]|2\d|3[01])\.|^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|^198\.1[89]\.|^(22[4-9]|2[3-5]\d)\./;

/**
 * Adresser i det egna nätet eller på servern själv. IPv6: ospecificerad, loopback, unika lokala
 * (fc00::/7), länklokala (fe80::/10), multicast (ff00::/8) och adresser med en inbäddad
 * IPv4-adress (::ffff:, 64:ff9b::, 2002::), som skulle kunna peka var som helst.
 */
function isPrivateAddress(address: string): boolean {
  const ip = address.toLowerCase();
  if (ip.includes(':')) return ip === '::' || ip === '::1' || /^(f[cdf]|fe[89ab]|::ffff:|64:ff9b:|2002:)/.test(ip);
  return PRIVATE_IPV4.test(ip);
}

/** En vanlig webbadress till en namngiven sajt; adresser skrivna som IP-nummer eller lokala namn nekas. */
function checkedUrl(raw: string): URL {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    throw new HttpError('Ogiltig länk.', 400);
  }
  const host = url.hostname.toLowerCase();
  const local =
    !host.includes('.') ||
    host.endsWith('.') ||
    host.startsWith('[') ||
    /\.(local|internal|localhost)$/.test(host) ||
    isPrivateAddress(host);
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || local) {
    throw new HttpError('Ogiltig länk.', 400);
  }
  return url;
}

/** Ett namn kan peka på en adress i det egna nätet, så det slås upp innan sidan hämtas. */
async function requirePublicHost(host: string): Promise<void> {
  const lookups = await Promise.all([
    Deno.resolveDns(host, 'A').catch(() => []),
    Deno.resolveDns(host, 'AAAA').catch(() => [])
  ]);
  const addresses = lookups.flat();
  if (addresses.length === 0 || addresses.some(isPrivateAddress)) {
    throw new HttpError('Kunde inte hämta sidan.', 502);
  }
}

/** Läser högst MAX_BYTES, så att en mycket stor sida inte fyller minnet. */
async function readText(res: Response): Promise<string> {
  const reader = res.body?.getReader();
  if (!reader) return '';
  const decoder = new TextDecoder();
  let text = '';
  let size = 0;
  while (size < MAX_BYTES) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    text += decoder.decode(value, { stream: true });
  }
  await reader.cancel();
  return text;
}

/** Följer omdirigeringar själv, så att varje ny adress kontrolleras. */
async function fetchPage(start: URL): Promise<{ html: string; url: URL }> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    let url = start;
    for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
      await requirePublicHost(url.hostname);
      const res = await fetch(url, {
        headers: { 'User-Agent': UA, Accept: 'text/html,application/xhtml+xml,*/*' },
        redirect: 'manual',
        signal: ctrl.signal
      });
      const location = res.headers.get('location');
      if (res.status >= 300 && res.status < 400 && location) {
        await res.body?.cancel();
        url = checkedUrl(new URL(location, url).toString());
        continue;
      }
      if (!res.ok) throw new HttpError(`Sidan svarade ${res.status}.`, 502);
      return { html: await readText(res), url };
    }
    throw new HttpError('Sidan skickade vidare för många gånger.', 502);
  } catch (e) {
    if (e instanceof HttpError) throw e;
    throw new HttpError('Kunde inte hämta sidan.', 502);
  } finally {
    clearTimeout(timer);
  }
}

/** Sajter som ritar receptet i webbläsaren: hämta datan från deras API när HTML:en saknar ingredienser. */
async function fromSiteApi(url: URL, html: string): Promise<ParsedRecipe | null> {
  if (!url.hostname.endsWith('coop.se')) return null;
  const id = coopRecipeId(html);
  if (!id) return null;
  const res = await fetch(`${COOP_RECIPE_API}${id}?api-version=v1`, {
    headers: { 'User-Agent': UA, Accept: 'application/json' }
  });
  return res.ok ? parseCoopRecipe(await res.json()) : null;
}

/** Bilden som en fullständig https-adress, eller ingen bild alls (aldrig data:, javascript: o.d.). */
function imageUrl(raw: string | null, page: URL): string | null {
  if (!raw) return null;
  try {
    const u = new URL(raw, page);
    if (u.protocol === 'http:') u.protocol = 'https:';
    return u.protocol === 'https:' ? u.toString() : null;
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  try {
    await requireMember(req);
    const body = await req.json().catch(() => ({}));
    const link = checkedUrl(String(body.url ?? ''));
    const { html, url } = await fetchPage(link);
    let parsed = parseRecipeHtml(html);
    if (parsed.ingredients.length === 0) {
      const fromApi = await fromSiteApi(url, html).catch(() => null);
      if (fromApi) parsed = { ...parsed, ...fromApi, name: fromApi.name ?? parsed.name };
    }
    return json({
      recipe: {
        name: parsed.name ?? link.hostname,
        items: parsed.ingredients,
        image_url: imageUrl(parsed.imageUrl, url),
        source_url: link.toString()
      }
    });
  } catch (e) {
    const error = e instanceof HttpError ? e : new HttpError('Något gick fel.', 500);
    return json({ error: { message: error.message } }, error.status);
  }
});
