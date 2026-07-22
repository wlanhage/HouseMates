/** Supabase-klient (singleton). All data/auth/realtid går via denna. */
import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY } from '$env/static/public';

export const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false
  }
});

export interface ProfileRow {
  id: string; // auth uuid
  username: string; // kort id ('anna') – används som User.id i hela appen
  name: string;
  color: string;
  email: string;
}
