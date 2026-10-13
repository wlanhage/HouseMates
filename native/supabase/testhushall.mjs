// Skapar ett testhushåll i lokal Supabase, t.ex. efter att databasen återskapats:
// William (logga in i appen med kontot nedan) och partnern Anna (som partner.mjs spelar).
//   node native/supabase/testhushall.mjs
import { createClient } from '@supabase/supabase-js';
import { apiUrl, publishableKey, secretKey } from './local.mjs';

const WILLIAM = { email: 'william@example.com', password: 'hemligt-123', name: 'William' };
const ANNA = { email: 'anna@example.com', password: 'hemligt-123', name: 'Anna' };

const service = createClient(apiUrl, secretKey, { auth: { persistSession: false } });

/** Loggar in, och skapar först ett bekräftat konto om det saknas. */
async function signIn({ email, password, name }) {
  const client = createClient(apiUrl, publishableKey, { auth: { persistSession: false } });
  if ((await client.auth.signInWithPassword({ email, password })).error) {
    const { error } = await service.auth.admin.createUser({ email, password, email_confirm: true, user_metadata: { name } });
    if (error) throw error;
    const { error: signInError } = await client.auth.signInWithPassword({ email, password });
    if (signInError) throw signInError;
  }
  return client;
}

const william = await signIn(WILLIAM);
const anna = await signIn(ANNA);

let { data: household } = await william.from('households').select('invite_code').maybeSingle();
if (!household) {
  const { data, error } = await william.rpc('create_household');
  if (error) throw error;
  household = data;
}
const { count } = await anna.from('household_members').select('user_id', { count: 'exact', head: true });
if (!count) {
  const { error } = await anna.rpc('join_household', { p_code: household.invite_code });
  if (error) throw error;
}
console.log(`Klart. Logga in i appen som ${WILLIAM.email}; Anna är med i hushållet (kod ${household.invite_code}).`);
