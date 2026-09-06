<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { user, me } from '$lib/client/stores';
  import { refreshEvents } from '$lib/client/data';
  import { supabase } from '$lib/client/supabase';
  import { PUBLIC_SUPABASE_URL } from '$env/static/public';
  import { logout as authLogout, loadMe } from '$lib/client/auth';
  import { hhmm } from '$lib/client/dates';
  import type { SyncStatus, NotificationPrefs } from '$lib/types';

  /** Anropa en edge function; kasta med läsbart meddelande vid fel. */
  async function invoke<T>(name: string, body?: Record<string, unknown>): Promise<T> {
    const { data, error } = await supabase.functions.invoke(name, { body });
    if (error) {
      try {
        const ctx = (error as { context?: Response }).context;
        if (ctx) {
          const parsed = await ctx.json();
          throw new Error(parsed?.error?.message ?? 'Något gick fel.');
        }
      } catch (e) {
        if (e instanceof Error && e.message !== 'Något gick fel.') throw e;
      }
      throw new Error('Kunde inte nå servern.');
    }
    return data as T;
  }

  let busy = $state(false);

  // ── Notiser ──
  const pushSupported =
    typeof navigator !== 'undefined' &&
    'serviceWorker' in navigator &&
    typeof window !== 'undefined' &&
    'PushManager' in window &&
    'Notification' in window;
  let notifEnabled = $state(true);
  let quietFrom = $state('21:00');
  let quietTo = $state('07:30');
  let digestMinutes = $state(10);
  let subscribed = $state(false);
  let notifMsg = $state('');
  let prefsInit = false;

  $effect(() => {
    const p = $me?.prefs;
    if (p && !prefsInit) {
      prefsInit = true;
      notifEnabled = p.enabled;
      quietFrom = p.quiet_from;
      quietTo = p.quiet_to;
      digestMinutes = p.digest_minutes;
    }
  });

  onMount(async () => {
    if (pushSupported) {
      try {
        const reg = await navigator.serviceWorker.ready;
        subscribed = !!(await reg.pushManager.getSubscription());
      } catch {
        /* ingen SW i dev */
      }
    }
  });

  function urlB64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
    const padding = '='.repeat((4 - (base64.length % 4)) % 4);
    const b64 = (base64 + padding).replace(/-/g, '+').replace(/_/g, '/');
    const raw = atob(b64);
    const out = new Uint8Array(new ArrayBuffer(raw.length));
    for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
    return out;
  }

  async function savePrefs(patch: Partial<NotificationPrefs>) {
    const username = $user?.id;
    if (!username) return;
    await supabase.from('notification_prefs').update(patch).eq('username', username);
    void loadMe();
  }

  async function subscribePush() {
    notifMsg = '';
    const key = $me?.vapidPublicKey;
    if (!key) {
      notifMsg = 'Push är inte konfigurerat på servern.';
      return;
    }
    try {
      const perm = await Notification.requestPermission();
      if (perm !== 'granted') {
        notifMsg = 'Notiser nekades i webbläsaren.';
        return;
      }
      const reg = await navigator.serviceWorker.ready;
      const sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlB64ToUint8Array(key)
      });
      const json = sub.toJSON() as { endpoint: string; keys: { p256dh: string; auth: string } };
      const { error } = await supabase.from('push_subscriptions').upsert(
        {
          username: $user!.id,
          endpoint: json.endpoint,
          p256dh: json.keys.p256dh,
          auth: json.keys.auth,
          failed_at: null
        },
        { onConflict: 'endpoint' }
      );
      if (error) throw error;
      subscribed = true;
      notifMsg = 'Notiser aktiverade på den här enheten.';
    } catch {
      notifMsg = 'Kunde inte aktivera notiser (installera appen på hemskärmen på iPhone).';
    }
  }

  // Synkstatus
  let sync = $state<SyncStatus | null>(null);
  let syncing = $state(false);

  // CalDAV-wizard
  let step = $state<0 | 1>(0);
  let appleId = $state('');
  let appPassword = $state('');
  let calendars = $state<{ href: string; name: string }[]>([]);
  let chosen = $state('');
  let wizardBusy = $state(false);
  let wizardError = $state('');

  const connected = $derived(!!sync?.last_synced_at);

  onMount(loadSync);

  async function loadSync() {
    const username = $user?.id;
    if (!username) return;
    const { data } = await supabase
      .from('sync_state')
      .select('last_synced_at, failing_since, last_error')
      .eq('username', username)
      .maybeSingle();
    if (data) sync = data as SyncStatus;
  }

  async function manualSync() {
    syncing = true;
    try {
      await invoke('caldav-sync');
      await Promise.all([loadSync(), refreshEvents()]);
    } catch {
      await loadSync();
    } finally {
      syncing = false;
    }
  }

  async function discover(e: Event) {
    e.preventDefault();
    wizardError = '';
    if (!appleId || !appPassword) {
      wizardError = 'Ange Apple-ID och app-lösenord.';
      return;
    }
    wizardBusy = true;
    try {
      const res = await invoke<{ calendars: { href: string; name: string }[]; targetName: string }>(
        'caldav-setup',
        { appleId, appPassword }
      );
      calendars = res.calendars;
      chosen = res.calendars.find((c) => c.name === res.targetName)?.href ?? res.calendars[0]?.href ?? '';
      step = 1;
    } catch (err) {
      wizardError = err instanceof Error ? err.message : 'Något gick fel.';
    } finally {
      wizardBusy = false;
    }
  }

  async function selectCalendar() {
    wizardError = '';
    if (!chosen) return;
    wizardBusy = true;
    try {
      await invoke('caldav-select', { appleId, appPassword, href: chosen });
      appPassword = '';
      step = 0;
      await manualSync();
    } catch (err) {
      wizardError = err instanceof Error ? err.message : 'Något gick fel.';
    } finally {
      wizardBusy = false;
    }
  }

  // ── Receptimport via iPhone-genväg (nyckel i headern x-import-token) ──
  const importUrl = `${PUBLIC_SUPABASE_URL}/functions/v1/recipe-import`;
  let importToken = $state<string | null>(null);
  let tokenMsg = $state('');

  onMount(loadImportToken);

  async function loadImportToken() {
    const username = $user?.id;
    if (!username) return;
    const { data } = await supabase.from('import_tokens').select('token').eq('username', username).maybeSingle();
    importToken = data?.token ?? null;
  }

  async function newImportToken() {
    const username = $user?.id;
    if (!username) return;
    const token = crypto.randomUUID().replace(/-/g, '');
    const { error } = await supabase
      .from('import_tokens')
      .upsert({ username, token }, { onConflict: 'username' });
    tokenMsg = error ? 'Kunde inte spara nyckeln.' : '';
    if (!error) importToken = token;
  }

  async function copyText(text: string, label: string) {
    try {
      await navigator.clipboard.writeText(text);
      tokenMsg = `${label} kopierad.`;
    } catch {
      tokenMsg = 'Kunde inte kopiera – markera och kopiera manuellt.';
    }
  }

  async function logout() {
    busy = true;
    try {
      await authLogout();
      await goto(`${base}/login`);
    } finally {
      busy = false;
    }
  }
</script>

<svelte:head><title>Inställningar</title></svelte:head>

<h2 class="page-title">Inställningar</h2>

{#if $user}
  <div class="card" style="padding:1rem;display:flex;align-items:center;gap:0.75rem;margin-bottom:1rem">
    <span class="avatar" style={`background:${$user.color};width:40px;height:40px;font-size:1rem`}>
      {$user.name.charAt(0)}
    </span>
    <div>
      <div style="font-weight:700">{$user.name}</div>
      <div class="muted" style="font-size:0.85rem">Inloggad</div>
    </div>
  </div>
{/if}

<div class="section-title">Kalendersynk</div>
<div class="card" style="padding:1rem;margin-bottom:1rem">
  {#if connected && sync?.last_synced_at}
    <div class="row" style="justify-content:space-between">
      <div>
        <div style="font-weight:600">Senast synkad {hhmm(sync.last_synced_at)}</div>
        {#if sync.failing_since}
          <div style="color:var(--danger);font-size:0.85rem">Synken har problem – kontrollera lösenordet.</div>
        {/if}
      </div>
      <button class="btn" onclick={manualSync} disabled={syncing}>{syncing ? 'Synkar…' : 'Synka nu'}</button>
    </div>
  {:else}
    <p class="muted" style="margin-top:0">
      Koppla er delade iCloud-kalender. Skapa ett app-specifikt lösenord på
      account.apple.com → Logga in och säkerhet.
    </p>

    {#if step === 0}
      <form onsubmit={discover}>
        <div class="field">
          <label for="apple-id">Apple-ID (e-post)</label>
          <input id="apple-id" class="input" type="email" autocomplete="username" bind:value={appleId} placeholder="namn@icloud.com" />
        </div>
        <div class="field">
          <label for="app-pw">App-specifikt lösenord</label>
          <input id="app-pw" class="input" type="password" autocomplete="off" bind:value={appPassword} placeholder="xxxx-xxxx-xxxx-xxxx" />
        </div>
        {#if wizardError}<p class="error-text">{wizardError}</p>{/if}
        <button class="btn btn-primary btn-block" type="submit" disabled={wizardBusy}>
          {wizardBusy ? 'Hämtar kalendrar…' : 'Nästa'}
        </button>
      </form>
    {:else}
      <div class="field">
        <label for="cal">Välj kalender</label>
        <select id="cal" class="input" bind:value={chosen}>
          {#each calendars as c (c.href)}
            <option value={c.href}>{c.name}</option>
          {/each}
        </select>
      </div>
      {#if wizardError}<p class="error-text">{wizardError}</p>{/if}
      <div class="row" style="gap:0.5rem">
        <button class="btn" onclick={() => (step = 0)} disabled={wizardBusy}>Tillbaka</button>
        <button class="btn btn-primary" style="flex:1" onclick={selectCalendar} disabled={wizardBusy}>
          {wizardBusy ? 'Sparar…' : 'Koppla kalender'}
        </button>
      </div>
    {/if}
  {/if}
</div>

<div class="section-title">Notiser</div>
<div class="card" style="padding:1rem;margin-bottom:1rem">
  {#if !pushSupported}
    <div class="muted">
      Notiser stöds inte här. På iPhone: installera appen på hemskärmen först (se nedan).
    </div>
  {:else}
    <label class="notif-toggle">
      <span>Aktivera notiser</span>
      <input
        type="checkbox"
        bind:checked={notifEnabled}
        onchange={() => savePrefs({ enabled: notifEnabled })}
      />
    </label>

    {#if !subscribed}
      <button class="btn btn-block" style="margin:0.5rem 0" onclick={subscribePush}>
        Tillåt push på den här enheten
      </button>
    {:else}
      <div class="muted" style="font-size:0.85rem;margin-bottom:0.5rem">✓ Push aktiverat på den här enheten</div>
    {/if}
    {#if notifMsg}<p class="muted" style="font-size:0.85rem">{notifMsg}</p>{/if}

    <div class="row" style="gap:0.5rem;margin-top:0.5rem">
      <div class="field" style="flex:1;margin:0">
        <label for="qf">Tysta timmar från</label>
        <input id="qf" class="input" type="time" bind:value={quietFrom} onchange={() => savePrefs({ quiet_from: quietFrom })} />
      </div>
      <div class="field" style="flex:1;margin:0">
        <label for="qt">till</label>
        <input id="qt" class="input" type="time" bind:value={quietTo} onchange={() => savePrefs({ quiet_to: quietTo })} />
      </div>
    </div>
    <div class="field" style="margin-top:0.75rem">
      <label for="dm">Samla notiser i (minuter)</label>
      <input id="dm" class="input" type="number" min="0" max="120" bind:value={digestMinutes} onchange={() => savePrefs({ digest_minutes: digestMinutes })} />
    </div>
  {/if}
</div>

<div class="section-title">Recept från Safari</div>
<div class="card" style="padding:1rem;margin-bottom:1rem">
  <div class="muted" style="font-size:0.9rem;margin-bottom:0.75rem">
    En iPhone-genväg ("Spara till HouseMates" under Dela) sparar recept som favoriter. Den behöver
    adressen och din nyckel nedan – bygget beskrivs i <strong>RECEPT-GENVAG.md</strong>.
  </div>
  <div class="field">
    <span class="label-txt">Adress</span>
    <div class="token-row">
      <code class="token">{importUrl}</code>
      <button class="btn" onclick={() => copyText(importUrl, 'Adressen')}>Kopiera</button>
    </div>
  </div>
  <div class="field" style="margin-bottom:0.5rem">
    <span class="label-txt">Din nyckel</span>
    {#if importToken}
      <div class="token-row">
        <code class="token">{importToken}</code>
        <button class="btn" onclick={() => copyText(importToken!, 'Nyckeln')}>Kopiera</button>
      </div>
    {:else}
      <button class="btn btn-block" onclick={newImportToken}>Skapa nyckel</button>
    {/if}
  </div>
  {#if importToken}
    <button class="btn" style="padding:0.35rem 0.7rem;font-size:0.85rem" onclick={newImportToken}>Byt nyckel</button>
  {/if}
  {#if tokenMsg}<p class="muted" style="font-size:0.85rem;margin:0.5rem 0 0">{tokenMsg}</p>{/if}
</div>

<div class="section-title">Installera på iPhone</div>
<div class="card" style="padding:1rem;margin-bottom:1.5rem">
  <div class="muted">
    Öppna i Safari → Dela-knappen → <strong>Lägg till på hemskärmen</strong>. Krävs för push-notiser.
  </div>
</div>

<button class="btn btn-danger btn-block" onclick={logout} disabled={busy}>
  {busy ? 'Loggar ut…' : 'Logga ut'}
</button>

<style>
  .token-row {
    display: flex;
    gap: 0.5rem;
    align-items: center;
  }
  .token {
    flex: 1;
    min-width: 0;
    font-size: 0.78rem;
    padding: 0.5rem 0.6rem;
    background: var(--surface-2);
    border-radius: var(--radius-sm);
    overflow-wrap: anywhere;
    user-select: all;
  }
  .notif-toggle {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-weight: 600;
    padding: 0.2rem 0;
  }
  .notif-toggle input {
    width: 20px;
    height: 20px;
  }
</style>
