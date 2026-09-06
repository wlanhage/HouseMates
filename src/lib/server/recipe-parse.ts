/**
 * Receptsida (HTML) → namn, bild, ingredienser. Ren modul → testbar.
 * Speglas i supabase/functions/_shared/recipe.ts (Deno) – håll dem lika.
 *
 * Nästan alla receptsajter bäddar in schema.org/Recipe som JSON-LD; det är
 * primärkällan. Saknas den: og:title / <title>, og:image och en lös sökning
 * efter "recipeIngredient" i sidans inbäddade state-JSON.
 */

export interface ParsedRecipe {
  name: string | null;
  imageUrl: string | null;
  ingredients: string[];
}

type Json = Record<string, unknown>;

const ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' '
};

export function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (m, code: string) => {
    if (code[0] === '#') {
      const n = code[1].toLowerCase() === 'x' ? parseInt(code.slice(2), 16) : parseInt(code.slice(1), 10);
      return Number.isFinite(n) ? String.fromCodePoint(n) : m;
    }
    return ENTITIES[code.toLowerCase()] ?? m;
  });
}

const clean = (s: string): string => decodeEntities(s).replace(/\s+/g, ' ').trim();

function jsonLdBlocks(html: string): string[] {
  const out: string[] = [];
  const re = /<script[^>]*type\s*=\s*["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html))) out.push(m[1]);
  return out;
}

function isRecipe(node: Json): boolean {
  const t = node['@type'];
  if (typeof t === 'string') return t.toLowerCase() === 'recipe';
  return Array.isArray(t) && t.some((x) => typeof x === 'string' && x.toLowerCase() === 'recipe');
}

/** Hitta första Recipe-objektet: toppnivå, i listor, @graph eller mainEntity. */
function findRecipe(node: unknown, depth = 0): Json | null {
  if (depth > 6 || !node || typeof node !== 'object') return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const hit = findRecipe(item, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  const obj = node as Json;
  if (isRecipe(obj)) return obj;
  for (const key of ['@graph', 'mainEntity', 'mainEntityOfPage', 'itemListElement']) {
    const hit = findRecipe(obj[key], depth + 1);
    if (hit) return hit;
  }
  return null;
}

function imageOf(v: unknown): string | null {
  if (!v) return null;
  if (typeof v === 'string') return v.trim() || null;
  if (Array.isArray(v)) return imageOf(v[0]);
  if (typeof v === 'object') {
    const o = v as Json;
    return imageOf(o.url ?? o.contentUrl ?? o['@id']);
  }
  return null;
}

function ingredientsOf(v: unknown): string[] {
  const list = Array.isArray(v) ? v : typeof v === 'string' ? v.split(/\r?\n/) : [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of list) {
    const text = typeof raw === 'string' ? raw : typeof raw === 'object' && raw ? String((raw as Json).name ?? '') : '';
    const line = clean(text);
    const key = line.toLowerCase();
    if (line && !seen.has(key)) {
      seen.add(key);
      out.push(line);
    }
  }
  return out;
}

/**
 * Lös fallback för sajter utan JSON-LD som ändå bäddar in receptdatan i ett
 * state-blob (t.ex. Arla): hitta "recipeIngredient": [...] och parsa arrayen.
 */
function looseIngredients(html: string): string[] {
  const text = decodeEntities(html);
  const re = /"recipeIngredient"\s*:\s*\[/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const arr = jsonArrayAt(text, m.index + m[0].length - 1);
    if (!arr) continue;
    try {
      const list = ingredientsOf(JSON.parse(arr));
      if (list.length) return list;
    } catch {
      /* prova nästa träff */
    }
  }
  return [];
}

/** Text för JSON-arrayen som börjar på index start ('['), med hänsyn till strängar. */
function jsonArrayAt(text: string, start: number): string | null {
  let depth = 0;
  let inStr = false;
  for (let i = start; i < text.length && i < start + 20_000; i++) {
    const ch = text[i];
    if (inStr) {
      if (ch === '\\') i++;
      else if (ch === '"') inStr = false;
    } else if (ch === '"') inStr = true;
    else if (ch === '[') depth++;
    else if (ch === ']' && --depth === 0) return text.slice(start, i + 1);
  }
  return null;
}

function meta(html: string, property: string): string | null {
  const re = new RegExp(
    `<meta[^>]+(?:property|name)\\s*=\\s*["']${property}["'][^>]*content\\s*=\\s*["']([^"']*)["']|` +
      `<meta[^>]+content\\s*=\\s*["']([^"']*)["'][^>]*(?:property|name)\\s*=\\s*["']${property}["']`,
    'i'
  );
  const m = re.exec(html);
  const v = m?.[1] ?? m?.[2];
  return v ? clean(v) || null : null;
}

function titleTag(html: string): string | null {
  const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  return m ? clean(m[1]) || null : null;
}

export function parseRecipeHtml(html: string): ParsedRecipe {
  for (const block of jsonLdBlocks(html)) {
    let data: unknown;
    try {
      data = JSON.parse(block.trim());
    } catch {
      continue;
    }
    const recipe = findRecipe(data);
    if (!recipe) continue;
    const name = typeof recipe.name === 'string' ? clean(recipe.name) : null;
    return {
      name: name || null,
      imageUrl: imageOf(recipe.image),
      ingredients: ingredientsOf(recipe.recipeIngredient)
    };
  }
  return {
    name: meta(html, 'og:title') ?? titleTag(html),
    imageUrl: meta(html, 'og:image'),
    ingredients: looseIngredients(html)
  };
}
