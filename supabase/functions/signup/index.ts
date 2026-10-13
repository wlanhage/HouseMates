/**
 * Nytt konto: användarnamn, namn och lösenord. Inloggningen bygger på
 * användarnamn (<namn>@housemates.local), så kontot skapas bekräftat direkt
 * utan mejl. Hushåll skapas eller väljs efter inloggning (create/join_household).
 */
import { serviceClient, jsonResponse, handleOptions, HttpError } from '../_shared/util.ts';

const LOGIN_EMAIL_DOMAIN = 'housemates.local';

Deno.serve(async (req) => {
  const opt = handleOptions(req);
  if (opt) return opt;
  try {
    const body = await req.json().catch(() => ({}));
    const username = String(body.username ?? '').trim().toLowerCase();
    const name = String(body.name ?? '').trim();
    const password = String(body.password ?? '');

    if (!/^[a-z0-9_-]{2,20}$/.test(username)) {
      throw new HttpError('validation', 'Användarnamnet får bara innehålla a–z, 0–9, - och _ (2–20 tecken).', 400);
    }
    if (name.length < 1 || name.length > 40) throw new HttpError('validation', 'Ange ditt namn.', 400);
    if (password.length < 8) throw new HttpError('validation', 'Lösenordet måste ha minst 8 tecken.', 400);

    const svc = serviceClient();
    const { data: taken } = await svc.from('profiles').select('id').eq('username', username).maybeSingle();
    if (taken) throw new HttpError('duplicate', 'Användarnamnet är upptaget.', 409);

    const email = `${username}@${LOGIN_EMAIL_DOMAIN}`;
    const { data: created, error } = await svc.auth.admin.createUser({ email, password, email_confirm: true });
    if (error || !created.user) throw new HttpError('duplicate', 'Användarnamnet är upptaget.', 409);

    const userId = created.user.id;
    const { error: profileError } = await svc
      .from('profiles')
      .insert({ id: userId, username, name, color: '#378ADD', email });
    if (profileError) {
      await svc.auth.admin.deleteUser(userId);
      throw new HttpError('db', 'Kunde inte skapa kontot.', 500);
    }
    await svc.from('notification_prefs').insert({ username });
    await svc.from('sync_state').insert({ username });

    return jsonResponse({ ok: true });
  } catch (e) {
    if (e instanceof HttpError) return e.response();
    return jsonResponse({ error: { message: String(e) } }, 500);
  }
});
