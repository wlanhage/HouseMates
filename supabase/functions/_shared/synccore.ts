/** Upsert av CalDAV-resurser till events-cachen (delas av sync + skrivflöde). */
// @ts-expect-error npm-import i Deno
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { parseResource } from './ics.ts';

const DAY = 86_400_000;
export const EXPAND_START = () => new Date(Date.now() - 30 * DAY);
export const EXPAND_END = () => new Date(Date.now() + 180 * DAY);
export const QUERY_START = () => new Date(Date.now() - 60 * DAY);
export const QUERY_END = () => new Date(Date.now() + 365 * DAY);

export function createdByFromUid(uid: string, usernames: string[]): string | null {
  for (const u of usernames) if (uid.startsWith(`app-${u}-`)) return u;
  return null;
}

/** Parsa + upserta EN resurs; städar bort försvunna förekomster. Returnerar master-radens id. */
export async function upsertResource(
  svc: SupabaseClient,
  data: string,
  href: string,
  etag: string | null,
  usernames: string[]
): Promise<string | null> {
  let rows;
  try {
    rows = parseResource(data, EXPAND_START(), EXPAND_END());
  } catch {
    return null; // trasig ICS – hoppa över
  }
  if (!rows.length) return null;

  const ts = new Date().toISOString();
  const uid = rows[0].caldav_uid;
  const payload = rows.map((r) => ({
    caldav_uid: r.caldav_uid,
    recurrence_id: r.recurrence_id,
    caldav_href: href,
    etag,
    title: r.title,
    location: r.location,
    notes: r.notes,
    all_day: r.all_day,
    start_ts: r.start_ts,
    end_ts: r.end_ts,
    start_date: r.start_date,
    end_date: r.end_date,
    created_by: createdByFromUid(r.caldav_uid, usernames),
    raw_ics: data,
    synced_at: ts,
    updated_at: ts,
    deleted_at: null,
    deleted_by: null
  }));

  const { error } = await svc
    .from('events')
    .upsert(payload, { onConflict: 'caldav_uid,recurrence_id' });
  if (error) throw error;

  // Städa förekomster som inte längre finns i resursen.
  // OBS: tom sträng ('' = icke-återkommande) kan inte uttryckas säkert i en
  // PostgREST in-lista – hantera den med neq separat.
  const nonEmpty = rows.map((r) => r.recurrence_id).filter((r) => r !== '');
  const keepsEmpty = rows.some((r) => r.recurrence_id === '');
  let del = svc.from('events').delete().eq('caldav_uid', uid);
  if (nonEmpty.length) {
    const keep = nonEmpty.map((r) => `"${r.replaceAll('"', '')}"`).join(',');
    del = del.not('recurrence_id', 'in', `(${keep})`);
  }
  if (keepsEmpty) del = del.neq('recurrence_id', '');
  const { error: delError } = await del;
  if (delError) throw delError;

  const master = rows.find((r) => r.recurrence_id === '') ?? rows[0];
  const { data: row } = await svc
    .from('events')
    .select('id')
    .eq('caldav_uid', master.caldav_uid)
    .eq('recurrence_id', master.recurrence_id)
    .maybeSingle();
  return row?.id ?? null;
}

/** Hämta en events-rad med alla kolumner (för svar till klienten). */
export async function getEventRow(svc: SupabaseClient, id: string) {
  const { data } = await svc.from('events').select('*').eq('id', id).maybeSingle();
  return data;
}
