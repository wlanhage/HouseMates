<script lang="ts">
  import { onMount } from 'svelte';
  import { goto, invalidateAll } from '$app/navigation';
  import { user, me } from '$lib/client/stores';
  import { refreshEvents } from '$lib/client/data';
  import { apiGet, apiPost, apiPatch, ApiError } from '$lib/client/api';
  import { hhmm } from '$lib/client/dates';
  import type { SyncStatus, NotificationPrefs } from '$lib/types';

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
    try {
      await apiPatch('/api/push/prefs', patch);
    } catch {
      /* offline */
    }
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
      await apiPost('/api/push/subscribe', sub.toJSON());
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
    try {
      sync = await apiGet<SyncStatus>('/api/sync/status');
    } catch {
      /* offline */
    }
  }

  async function manualSync() {
    syncing = true;
    try {
      sync = await apiPost<SyncStatus>('/api/sync/run');
      await refreshEvents();
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
      const res = await apiPost<{ calendars: { href: string; name: string }[]; targetName: string }>(
        '/api/caldav/setup',
        { appleId, appPassword }
      );
      calendars = res.calendars;
      chosen = res.calendars.find((c) => c.name === res.targetName)?.href ?? res.calendars[0]?.href ?? '';
      step = 1;
    } catch (err) {
      wizardError = err instanceof ApiError ? err.message : 'Något gick fel.';
    } finally {
      wizardBusy = false;
    }
  }

  async function selectCalendar() {
    wizardError = '';
    if (!chosen) return;
    wizardBusy = true;
    try {
      await apiPost('/api/caldav/select', { appleId, appPassword, href: chosen });
      appPassword = '';
      step = 0;
      await manualSync();
    } catch (err) {
      wizardError = err instanceof ApiError ? err.message : 'Något gick fel.';
    } finally {
      wizardBusy = false;
    }
  }

  async function logout() {
    busy = true;
    try {
      await apiPost('/api/auth/logout');
      await invalidateAll();
      await goto('/login');
    } finally {
      busy = false;
    }
  }
</script>

<svelte:head><title>Inställningar</title></svelte:head>

<h2 style="font-size:1.5rem;margin-bottom:1rem">Inställningar</h2>

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
