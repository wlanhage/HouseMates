// Spelar partnern "Anna" mot lokal Supabase, så att en simulator räcker för att testa realtid och notiser.
//   node native/supabase/partner.mjs join <din-epost>   – Anna går med i ditt hushåll
//   node native/supabase/partner.mjs add Bröd           – Anna lägger till en vara
//   node native/supabase/partner.mjs check Mjölk        – Anna bockar av en vara
//   node native/supabase/partner.mjs todo Boka tvättid  – Anna lägger till en uppgift
//   node native/supabase/partner.mjs chore Dammsuga     – Anna lägger till en städsyssla varje vecka
//   node native/supabase/partner.mjs done Dammsuga      – Anna gör klart en uppgift eller städsyssla
//   node native/supabase/partner.mjs recipe <länk>      – Anna sparar ett recept i Våra middagar
//                                                         (kräver `supabase functions serve`)
//   node native/supabase/partner.mjs leave              – Anna lämnar hushållet
import { createClient } from '@supabase/supabase-js';
import { apiUrl, publishableKey, secretKey } from './local.mjs';
import { randomUUID } from 'node:crypto';

const ANNA = { email: 'anna@example.com', password: 'hemligt-123' };

const [command, ...rest] = process.argv.slice(2);
const argument = rest.join(' ');
const anna = createClient(apiUrl, publishableKey, { auth: { persistSession: false } });

const signIn = await anna.auth.signInWithPassword(ANNA);
if (signIn.error) {
  const { error } = await anna.auth.signUp({ ...ANNA, options: { data: { name: 'Anna' } } });
  if (error) throw error;
}

const { count: memberships } = await anna.from('household_members').select('user_id', { count: 'exact', head: true });
if (command !== 'join' && !memberships) {
  console.log('Anna är inte med i något hushåll än. Kör först: node native/supabase/partner.mjs join <din-epost>');
  process.exit(1);
}

if (command === 'join') {
  const service = createClient(apiUrl, secretKey, { auth: { persistSession: false } });
  const { data: users } = await service.auth.admin.listUsers();
  const owner = users.users.find((u) => u.email === argument);
  if (!owner) throw new Error(`Hittar ingen användare med e-post ${argument}`);
  const { data: membership } = await service.from('household_members').select('household_id').eq('user_id', owner.id).single();
  const { data: household } = await service.from('households').select('invite_code').eq('id', membership.household_id).single();
  const { error } = await anna.rpc('join_household', { p_code: household.invite_code });
  console.log(error ? `Kunde inte gå med: ${error.message}` : `Anna gick med via koden ${household.invite_code}`);
} else if (command === 'add') {
  const { error } = await anna.from('shopping_items').insert({ id: randomUUID(), name: argument });
  console.log(error ? `Fel: ${error.message}` : `Anna la till ${argument}`);
} else if (command === 'check') {
  const { data, error } = await anna.from('shopping_items').update({ checked: true })
    .ilike('name', argument).eq('checked', false).is('deleted_at', null).select('name');
  console.log(error ? `Fel: ${error.message}` : `Anna bockade av ${data.map((d) => d.name).join(', ') || 'inget'}`);
} else if (command === 'todo') {
  const { error } = await anna.from('todos').insert({ id: randomUUID(), title: argument });
  console.log(error ? `Fel: ${error.message}` : `Anna la till uppgiften ${argument}`);
} else if (command === 'chore') {
  const { error } = await anna.from('chores').insert({ id: randomUUID(), title: argument, interval_days: 7 });
  console.log(error ? `Fel: ${error.message}` : `Anna la till städsysslan ${argument}`);
} else if (command === 'done') {
  const todos = await anna.from('todos').update({ done: true })
    .ilike('title', argument).eq('done', false).is('deleted_at', null).select('title');
  const chores = await anna.from('chores').update({ last_done_at: new Date().toISOString() })
    .ilike('title', argument).is('deleted_at', null).select('title');
  const error = todos.error ?? chores.error;
  const done = [...todos.data ?? [], ...chores.data ?? []].map((row) => row.title);
  console.log(error ? `Fel: ${error.message}` : `Anna gjorde klart ${done.join(', ') || 'inget'}`);
} else if (command === 'recipe') {
  const { data, error } = await anna.functions.invoke('recipe-import', { body: { url: argument } });
  if (error) {
    console.log(`Fel: ${(await error.context?.json?.())?.error?.message ?? error.message}`);
  } else {
    const { recipe } = data;
    const saved = await anna.from('favorites').insert({ id: randomUUID(), ...recipe });
    console.log(saved.error ? `Fel: ${saved.error.message}` : `Anna sparade ${recipe.name} (${recipe.items.length} varor)`);
  }
} else if (command === 'leave') {
  const { error } = await anna.rpc('leave_household');
  console.log(error ? `Fel: ${error.message}` : 'Anna lämnade hushållet');
} else {
  console.log('Användning: join <epost> | add <vara> | check <vara> | todo <uppgift> | chore <syssla> | done <titel> | recipe <länk> | leave');
}
