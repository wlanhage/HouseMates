<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { env } from '$env/dynamic/public';
  import { pwaInfo } from 'virtual:pwa-info';
  import BottomNav from '$lib/components/BottomNav.svelte';
  import UndoToast from '$lib/components/UndoToast.svelte';
  import CreateSheets from '$lib/components/CreateSheets.svelte';
  import PullToRefresh from '$lib/components/PullToRefresh.svelte';
  import { user, me, online, trackOnline } from '$lib/client/stores';
  import { apiGet, apiPost } from '$lib/client/api';
  import { refreshAll } from '$lib/client/data';
  import { startSSE } from '$lib/client/sse';
  import { hydrateFromMirror, startMirrorSync } from '$lib/client/mirror';
  import { replayOutbox } from '$lib/client/outbox';
  import { hhmm } from '$lib/client/dates';
  import type { MeResponse } from '$lib/types';

  let { data, children } = $props();

  const appName = env.PUBLIC_APP_NAME || 'Planeraren';
  const webManifestLink = pwaInfo ? pwaInfo.webManifest.linkTag : '';

  // Håll user-storen i synk med server-load.
  $effect(() => {
    user.set(data.user ?? null);
  });

  const isLogin = $derived($page.url.pathname === '/login');

  onMount(() => {
    const stop = trackOnline();
    // Registrera service worker (PWA-installerbarhet + offline-appskal, M3).
    import('virtual:pwa-register').then(({ registerSW }) => {
      registerSW({ immediate: true });
    });
    return stop;
  });

  // Hämta partner/prefs/syncstatus när inloggad.
  $effect(() => {
    if (data.user) {
      apiGet<MeResponse>('/api/me')
        .then((r) => me.set(r))
        .catch(() => {});
    } else {
      me.set(null);
    }
  });

  // Offline-first: spegel → replay → refetch → realtidsström. Städar vid logout.
  $effect(() => {
    if (!data.user) return;
    let cancelled = false;
    let stopMirror = () => {};
    let stopSSE = () => {};
    const onOnline = () => void replayThenRefresh();

    (async () => {
      await hydrateFromMirror(); // rendera ur spegeln direkt
      if (cancelled) return;
      stopMirror = startMirrorSync();
      await replayThenRefresh(); // spela upp kön, hämta färskt
      if (cancelled) return;
      stopSSE = startSSE();
    })();

    window.addEventListener('online', onOnline);
    return () => {
      cancelled = true;
      stopMirror();
      stopSSE();
      window.removeEventListener('online', onOnline);
    };
  });

  async function replayThenRefresh() {
    await replayOutbox();
    await refreshAll();
  }

  // Pull-to-refresh: trigga synk + hämta allt.
  async function pullRefresh() {
    try {
      await apiPost('/api/sync/run');
    } catch {
      /* ingen kalender kopplad / offline */
    }
    await refreshAll();
  }

  // Synkbanner: failing_since äldre än 1 timme.
  const syncTrouble = $derived.by(() => {
    const fs = $me?.syncStatus.failing_since;
    if (!fs) return null;
    if (Date.now() - new Date(fs).getTime() < 60 * 60 * 1000) return null;
    return hhmm(fs);
  });
</script>

<svelte:head>
  <!-- eslint-disable-next-line svelte/no-at-html-tags -->
  {@html webManifestLink}
</svelte:head>

{#if isLogin}
  {@render children()}
{:else}
  <div
    class="app-shell"
    style={`--nav-active:${$user?.color ?? 'var(--accent)'};--pair-a:${$user?.color ?? '#d4537e'};--pair-b:${$me?.partner?.color ?? '#378add'}`}
  >
    <header class="topbar">
      <span class="brand">
        <span class="pair" aria-hidden="true"><i></i><i></i></span>
        <h1>{appName}</h1>
      </span>
      <a class="icon-btn" href="/installningar" aria-label="Inställningar">
        <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="3" />
          <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.9l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-2.9 1.2 2 2 0 0 1-4 0 1.7 1.7 0 0 0-2.9-1.2l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-1.5-1H3a2 2 0 0 1 0-4h.1A1.7 1.7 0 0 0 4.6 9a1.7 1.7 0 0 0-.3-1.9l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1A1.7 1.7 0 0 0 10 4.6a1.7 1.7 0 0 0 1-1.5V3a2 2 0 0 1 4 0v.1a1.7 1.7 0 0 0 2.9 1.2l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.9 1.7 1.7 0 0 0 1.5 1h.1a2 2 0 0 1 0 4h-.1a1.7 1.7 0 0 0-1.4 1z" />
        </svg>
      </a>
    </header>

    {#if !$online}
      <div class="banner banner-offline">
        <span>📴</span> Du är offline – ändringar sparas och synkas sen.
      </div>
    {/if}
    {#if syncTrouble}
      <div class="banner banner-sync">
        <span>⚠️</span> Kalendersynken har problem sedan {syncTrouble} – kontrollera lösenordet i Inställningar.
      </div>
    {/if}

    <main class="content" class:content-lock={$page.url.pathname === '/'}>
      <PullToRefresh onrefresh={pullRefresh}>
        {@render children()}
      </PullToRefresh>
    </main>

    <BottomNav />
    <UndoToast />
    <CreateSheets />
  </div>
{/if}
