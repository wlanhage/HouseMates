// Röktest mot lokal Supabase (native): två personer bildar hushåll, en tredje ska inte se något.
// Kör: (cd native && supabase start) && node native/supabase/smoke.mjs
import { createClient } from '@supabase/supabase-js';
import { apiUrl, publishableKey, secretKey } from './local.mjs';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';


const run = Date.now();
const service = createClient(apiUrl, secretKey, { auth: { persistSession: false } });

async function signUp(name) {
  const client = createClient(apiUrl, publishableKey, { auth: { persistSession: false } });
  const { data, error } = await client.auth.signUp({
    email: `${name.toLowerCase()}-${run}@example.com`,
    password: 'hemligt-123',
    options: { data: { name } }
  });
  assert.ifError(error);
  return { client, id: data.user.id };
}

const step = (text) => console.log(`✓ ${text}`);

const anna = await signUp('Anna');
const erik = await signUp('Erik');
const eva = await signUp('Eva');

const { data: profile } = await anna.client.from('profiles').select('name').eq('id', anna.id).single();
assert.equal(profile.name, 'Anna');
step('profil skapas från namnet vid registrering');

const { data: household, error: createError } = await anna.client.rpc('create_household');
assert.ifError(createError);
assert.match(household.invite_code, /^[A-HJ-NP-Z2-9]{6}$/);
step(`Anna skapar hushåll med kod ${household.invite_code}`);

const { error: joinError } = await erik.client.rpc('join_household', { p_code: household.invite_code.toLowerCase() });
assert.ifError(joinError);
step('Erik går med (koden är skiftlägesokänslig)');

const { error: fullError } = await eva.client.rpc('join_household', { p_code: household.invite_code });
assert.match(fullError?.message ?? '', /redan två medlemmar/);
step('Eva nekas: hushållet är fullt');

const { data: annasView } = await anna.client.from('profiles').select('name').order('name');
assert.deepEqual(annasView.map((p) => p.name), ['Anna', 'Erik']);
step('Anna ser sin och Eriks profil, inte Evas');

const milk = randomUUID();
assert.ifError((await anna.client.from('shopping_items').insert({ id: milk, name: '  Mjölk ' })).error);
const duplicate = await erik.client.from('shopping_items').insert({ id: randomUUID(), name: 'mjölk' });
assert.equal(duplicate.error?.code, '23505');
step('vara läggs till trimmad; dubblett (skiftlägesokänsligt) avvisas med 23505');

assert.ifError((await erik.client.from('shopping_items').update({ checked: true, checked_by: anna.id }).eq('id', milk)).error);
const { data: checkedMilk } = await anna.client.from('shopping_items').select('*').eq('id', milk).single();
assert.equal(checkedMilk.checked_by, erik.id);
assert.equal(checkedMilk.created_by, anna.id);
step('Erik bockar av; checked_by sätts på servern trots att klienten skickade Anna');

const bread = randomUUID();
assert.ifError((await erik.client.from('shopping_items').insert({ id: bread, name: 'Bröd', checked: true, checked_by: anna.id })).error);
const { data: insertedChecked } = await anna.client.from('shopping_items').select('checked_by').eq('id', bread).single();
assert.equal(insertedChecked.checked_by, erik.id);
step('även en vara som skapas avbockad får rätt checked_by');

const { data: evasView } = await eva.client.from('shopping_items').select('id');
assert.equal(evasView.length, 0);
const sneaky = await eva.client.from('shopping_items').insert({ id: randomUUID(), name: 'Smuggel', household_id: household.id });
assert.ok(sneaky.error, 'Eva får inte skriva i någon annans hushåll');
step('Eva ser inga varor och kan inte skriva i hushållet');

assert.ifError((await anna.client.rpc('log_calendar_activity', {
  p_type: 'event.created', p_event_uid: 'uid-1', p_title: 'Tandläkare', p_start: '2026-10-07T12:00:00Z'
})).error);
const badType = await anna.client.rpc('log_calendar_activity', { p_type: 'event.hacked', p_event_uid: 'x', p_title: 'x', p_start: null });
assert.ok(badType.error);
step('kalenderaktivitet loggas; okänd typ avvisas');

const { data: queue } = await service
  .from('notification_queue')
  .select('recipient, send_after, activity:activity_log(type, actor)')
  .is('sent_at', null)
  .in('recipient', [anna.id, erik.id]);
const toErik = queue.filter((q) => q.recipient === erik.id).map((q) => q.activity.type).sort();
const toAnna = queue.filter((q) => q.recipient === anna.id).map((q) => q.activity.type);
assert.deepEqual(toErik, ['event.created', 'shopping.added']);
assert.deepEqual(toAnna.sort(), ['shopping.added', 'shopping.checked']);
assert.equal(new Set(queue.filter((q) => q.recipient === erik.id).map((q) => q.send_after)).size, 1);
step('notiskö: Erik får Annas händelser, Anna får Eriks, med gemensam sändtid (glidande fönster)');

assert.ifError((await anna.client.from('shopping_items').update({ deleted_at: new Date().toISOString() }).eq('id', milk)).error);
const { count: archived } = await service
  .from('activity_log').select('id', { count: 'exact', head: true })
  .eq('entity_id', milk).eq('type', 'shopping.deleted');
assert.equal(archived, 0);
step('att tömma en bockad vara ger ingen notis');

assert.ifError((await anna.client.rpc('set_calendar_link', { p_title: 'Vi två', p_uids: ['a', 'b'] })).error);
const { data: erikSees } = await erik.client.from('households').select('calendar_title, calendar_event_uids').single();
assert.deepEqual(erikSees, { calendar_title: 'Vi två', calendar_event_uids: ['a', 'b'] });
step('kalenderkopplingen som Anna sparar syns för Erik');

const token = `token-${run}`;
assert.ifError((await anna.client.rpc('register_device', { p_token: token })).error);
assert.ifError((await erik.client.rpc('register_device', { p_token: token })).error);
const { data: device } = await service.from('device_tokens').select('user_id').eq('token', token).single();
assert.equal(device.user_id, erik.id);
const { data: hidden } = await anna.client.from('device_tokens').select('token');
assert.equal(hidden.length, 0);
step('enhetstoken följer den som loggat in senast och är osynlig för klienter');

const notLoggedIn = createClient(apiUrl, publishableKey, { auth: { persistSession: false } });
assert.ok((await notLoggedIn.rpc('delete_account')).error);
step('radering kräver inloggning');

const count = async (table, column, value) =>
  (await service.from(table).select('*', { count: 'exact', head: true }).eq(column, value)).count;

assert.ifError((await erik.client.rpc('delete_account')).error);
assert.equal((await service.auth.admin.getUserById(erik.id)).data.user, null);
assert.equal(await count('profiles', 'id', erik.id), 0);
assert.equal(await count('household_members', 'user_id', erik.id), 0);
assert.equal(await count('device_tokens', 'user_id', erik.id), 0);
assert.equal(await count('activity_log', 'actor', erik.id), 0);
assert.equal(await count('notification_queue', 'recipient', erik.id), 0);
step('Erik raderar sitt konto: inloggning, profil, medlemskap, token, aktivitet och notiser borta');

const { data: breadAfter } = await anna.client.from('shopping_items').select('created_by, checked_by').eq('id', bread).single();
assert.deepEqual(breadAfter, { created_by: null, checked_by: null });
assert.equal(await count('households', 'id', household.id), 1);
const { data: annaAlone } = await anna.client.from('profiles').select('name');
assert.deepEqual(annaAlone.map((p) => p.name), ['Anna']);
step('Annas hushåll och varan Erik la till finns kvar, utan koppling till Erik');

assert.ifError((await anna.client.rpc('delete_account')).error);
assert.equal(await count('households', 'id', household.id), 0);
assert.equal(await count('shopping_items', 'household_id', household.id), 0);
assert.equal(await count('activity_log', 'household_id', household.id), 0);
step('Anna var sist kvar: hushållet, listan och historiken raderas med henne');

assert.ifError((await eva.client.rpc('delete_account')).error);
assert.equal((await service.auth.admin.getUserById(eva.id)).data.user, null);
step('konto utan hushåll går också att radera');

console.log('\nAlla kontroller gick igenom.');
