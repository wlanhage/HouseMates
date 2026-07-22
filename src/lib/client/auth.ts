/**
 * Auth-lager ovanpå Supabase: login med användarval + lösenord,
 * profiluppslag (auth-uuid ↔ username) och sessionbevakning.
 */
import { supabase, type ProfileRow } from './supabase';
import { user, me } from './stores';
import { PUBLIC_VAPID_KEY } from '$env/static/public';
import type { MeResponse, User } from '$lib/types';

const toUser = (p: ProfileRow): User => ({ id: p.username, name: p.name, color: p.color });

/** De två profilerna (för loginväljaren – läsbar utan inloggning). */
export async function fetchProfiles(): Promise<ProfileRow[]> {
  const { data, error } = await supabase
    .from('profiles')
    .select('id, username, name, color, email')
    .order('username');
  if (error) throw error;
  return data as ProfileRow[];
}

export async function login(email: string, password: string): Promise<string | null> {
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return 'Fel användare eller lösenord.';
  await loadMe();
  return null;
}

/** Auth-konton följer konventionen <användarnamn>@housemates.local. */
const LOGIN_EMAIL_DOMAIN = 'housemates.local';

/** Logga in med kort användarnamn (t.ex. "william"). */
export async function loginWithUsername(
  username: string,
  password: string
): Promise<string | null> {
  const u = username.trim().toLowerCase();
  if (!/^[a-z0-9_-]{2,20}$/.test(u)) return 'Fel användare eller lösenord.';
  return login(`${u}@${LOGIN_EMAIL_DOMAIN}`, password);
}

export async function logout(): Promise<void> {
  await supabase.auth.signOut();
  user.set(null);
  me.set(null);
}

/** Bygg me-objektet (user, partner, prefs, syncstatus) från Supabase. */
export async function loadMe(): Promise<MeResponse | null> {
  const { data: session } = await supabase.auth.getSession();
  const uid = session.session?.user.id;
  if (!uid) {
    user.set(null);
    me.set(null);
    return null;
  }

  const profiles = await fetchProfiles().catch(() => []);
  const mine = profiles.find((p) => p.id === uid);
  if (!mine) return null;
  const partner = profiles.find((p) => p.id !== uid) ?? null;

  const [{ data: prefs }, { data: sync }] = await Promise.all([
    supabase.from('notification_prefs').select('*').eq('username', mine.username).maybeSingle(),
    supabase.from('sync_state').select('*').eq('username', mine.username).maybeSingle()
  ]);

  const meResponse: MeResponse = {
    user: toUser(mine),
    partner: partner ? toUser(partner) : null,
    prefs: prefs
      ? {
          enabled: prefs.enabled,
          quiet_from: prefs.quiet_from,
          quiet_to: prefs.quiet_to,
          digest_minutes: prefs.digest_minutes
        }
      : { enabled: true, quiet_from: '21:00', quiet_to: '07:30', digest_minutes: 10 },
    syncStatus: {
      last_synced_at: sync?.last_synced_at ?? null,
      failing_since: sync?.failing_since ?? null,
      last_error: sync?.last_error ?? null
    },
    vapidPublicKey: PUBLIC_VAPID_KEY
  };
  user.set(meResponse.user);
  me.set(meResponse);
  return meResponse;
}

/** True om en session finns (utan nätverksanrop). */
export async function hasSession(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  return !!data.session;
}
