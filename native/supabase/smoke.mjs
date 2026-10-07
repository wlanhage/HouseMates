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

const annasPrefs = { user_id: anna.id, quiet_enabled: true, quiet_from: '22:30', quiet_to: '06:45', time_zone: 'Europe/Stockholm' };
assert.ifError((await anna.client.from('notification_prefs').upsert(annasPrefs)).error);
assert.ifError((await anna.client.from('notification_prefs').upsert({ ...annasPrefs, quiet_to: '07:15' })).error);
const { data: annasSaved } = await anna.client.from('notification_prefs').select('quiet_to').single();
assert.equal(annasSaved.quiet_to, '07:15');
const { data: erikSeesPrefs } = await erik.client.from('notification_prefs').select('user_id');
assert.equal(erikSeesPrefs.length, 0);
assert.ok((await erik.client.from('notification_prefs').upsert({ ...annasPrefs, quiet_enabled: false })).error);
assert.ok((await anna.client.from('notification_prefs').upsert({ ...annasPrefs, quiet_from: '25:00' })).error);
step('tysta timmar: sparas och ändras av ägaren, osynliga och oskrivbara för partnern, klockslag valideras');

const { data: colors } = await anna.client.from('profiles').select('name, color').order('name');
assert.deepEqual(colors, [{ name: 'Anna', color: '#378ADD' }, { name: 'Erik', color: '#D4537E' }]);
step('den som skapar hushållet blir blå, den som går med rosa');

const activityTypes = async (entityId) =>
  (await service.from('activity_log').select('type').eq('entity_id', entityId).order('id')).data.map((a) => a.type);

const todo = randomUUID();
assert.ifError((await erik.client.from('todos').insert({ id: todo, title: ' Boka tvättid ', assignee: anna.id, due_date: '2026-10-10', created_by: anna.id })).error);
assert.ifError((await anna.client.from('todos').update({ done: true, done_by: erik.id }).eq('id', todo)).error);
const { data: savedTodo } = await erik.client.from('todos').select('title, created_by, done_by, assignee').eq('id', todo).single();
assert.deepEqual(savedTodo, { title: 'Boka tvättid', created_by: erik.id, done_by: anna.id, assignee: anna.id });
assert.ok((await anna.client.from('todos').insert({ id: randomUUID(), title: 'Fel period', start_date: '2026-10-12', due_date: '2026-10-10' })).error);
assert.equal((await eva.client.from('todos').select('id')).data.length, 0);
assert.ifError((await anna.client.from('todos').update({ deleted_at: new Date().toISOString() }).eq('id', todo)).error);
assert.deepEqual(await activityTypes(todo), ['todo.created', 'todo.done']);
step('uppgift: aktörer sätts på servern, perioden valideras, Eva ser inget, att rensa en klar uppgift ger ingen notis');

const chore = randomUUID();
assert.ifError((await erik.client.from('chores').insert({ id: chore, title: 'Dammsuga', interval_days: 7, last_done_at: '2020-01-01T00:00:00Z' })).error);
const { data: newChore } = await anna.client.from('chores').select('last_done_at').eq('id', chore).single();
assert.equal(newChore.last_done_at, null);
const future = new Date(Date.now() + 86_400_000).toISOString();
assert.ifError((await anna.client.from('chores').update({ last_done_at: future, last_done_by: erik.id }).eq('id', chore)).error);
const { data: doneChore } = await erik.client.from('chores').select('last_done_at, last_done_by').eq('id', chore).single();
assert.equal(doneChore.last_done_by, anna.id);
assert.ok(new Date(doneChore.last_done_at).getTime() <= Date.now() + 1000, 'avbockning kan inte ligga i framtiden');
assert.ifError((await anna.client.from('chores').update({ last_done_at: '2026-09-01T10:00:00Z', last_done_by: erik.id }).eq('id', chore)).error);
const { data: undoneChore } = await anna.client.from('chores').select('last_done_at, last_done_by').eq('id', chore).single();
assert.equal(undoneChore.last_done_by, erik.id);
assert.ok((await anna.client.from('chores').insert({ id: randomUUID(), title: 'Fel intervall', interval_days: 0 })).error);
assert.deepEqual(await activityTypes(chore), ['chore.created', 'chore.done']);
step('städ: avbockning av den inloggade och aldrig i framtiden, ångra till ett tidigare datum ger ingen notis');

const tacos = randomUUID();
assert.ifError((await erik.client.from('favorites').insert({ id: tacos, name: ' Tacos ', items: ['500 g köttfärs', 'Tortillas'], created_by: anna.id })).error);
const { data: savedTacos } = await anna.client.from('favorites').select('name, items, created_by').eq('id', tacos).single();
assert.deepEqual(savedTacos, { name: 'Tacos', items: ['500 g köttfärs', 'Tortillas'], created_by: erik.id });
assert.ok((await erik.client.from('favorites').insert({ id: randomUUID(), name: 'Bild via http', image_url: 'http://exempel.se/bild.jpg' })).error);
assert.equal((await eva.client.from('favorites').select('id')).data.length, 0);
assert.deepEqual(await activityTypes(tacos), []);
assert.ifError((await anna.client.from('shopping_items').insert({ id: randomUUID(), name: 'Köttfärs', qty: '500 g' })).error);
assert.ok((await anna.client.from('shopping_items').insert({ id: randomUUID(), name: 'Mjöl', qty: 'x'.repeat(41) })).error);
step('middagar: skaparen sätts på servern, bilder bara över https, Eva ser inget, ingen notis; varor kan ha mängd');

const dinnerAssignee = randomUUID();
assert.ifError((await erik.client.from('event_assignees').insert({ id: dinnerAssignee, event_uid: 'MIDDAG-1', assignee: anna.id })).error);
assert.ok((await anna.client.from('event_assignees').insert({ id: randomUUID(), event_uid: 'MIDDAG-1', assignee: erik.id })).error);
assert.ifError((await anna.client.from('event_assignees').upsert({ id: dinnerAssignee, event_uid: 'MIDDAG-1', assignee: null })).error);
const { data: dinner } = await erik.client.from('event_assignees').select('assignee').eq('id', dinnerAssignee).single();
assert.equal(dinner.assignee, null);
assert.equal((await eva.client.from('event_assignees').select('id')).data.length, 0);
step('för vem: en person per händelse, partnern kan ändra till gemensamt, Eva ser inget');

const count = async (table, column, value) =>
  (await service.from(table).select('*', { count: 'exact', head: true }).eq(column, value)).count;

const lisa = await signUp('Lisa');
const olle = await signUp('Olle');
const { data: lisasHome } = await lisa.client.rpc('create_household');
assert.ifError((await olle.client.rpc('join_household', { p_code: lisasHome.invite_code })).error);
const coffee = randomUUID();
assert.ifError((await lisa.client.from('shopping_items').insert({ id: coffee, name: 'Kaffe' })).error);
assert.equal(await count('notification_queue', 'recipient', olle.id), 1);

assert.ifError((await olle.client.rpc('leave_household')).error);
assert.equal(await count('household_members', 'user_id', olle.id), 0);
assert.equal(await count('notification_queue', 'recipient', olle.id), 0);
assert.equal((await olle.client.from('shopping_items').select('id')).data.length, 0);
const { data: lisasHomeAfter } = await lisa.client.from('households').select('invite_code').single();
assert.notEqual(lisasHomeAfter.invite_code, lisasHome.invite_code);
const { data: lisaAlone } = await lisa.client.from('profiles').select('name');
assert.deepEqual(lisaAlone.map((p) => p.name), ['Lisa']);
assert.equal(await count('shopping_items', 'id', coffee), 1);
step('Olle lämnar: medlemskap och väntande notiser borta, listan kvar för Lisa, ny inbjudningskod');

const oldCode = await olle.client.rpc('join_household', { p_code: lisasHome.invite_code });
assert.match(oldCode.error?.message ?? '', /Hittade inget hushåll/);
assert.ifError((await olle.client.rpc('join_household', { p_code: lisasHomeAfter.invite_code })).error);
step('den gamla koden fungerar inte längre, den nya gör det');

assert.ifError((await olle.client.rpc('leave_household')).error);
assert.ifError((await lisa.client.rpc('leave_household')).error);
assert.equal(await count('households', 'id', lisasHome.id), 0);
assert.equal(await count('shopping_items', 'id', coffee), 0);
assert.ifError((await lisa.client.rpc('leave_household')).error);
step('den sista som lämnar tar hushållet och listan med sig; att lämna utan hushåll gör inget');

const notLoggedIn = createClient(apiUrl, publishableKey, { auth: { persistSession: false } });
assert.ok((await notLoggedIn.rpc('delete_account')).error);
assert.ok((await notLoggedIn.rpc('leave_household')).error);
step('radering och att lämna kräver inloggning');

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
