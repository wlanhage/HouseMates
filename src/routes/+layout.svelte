<script lang="ts">
  import '../app.css';
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { PUBLIC_APP_NAME } from '$env/static/public';
  import { pwaInfo } from 'virtual:pwa-info';
  import BottomNav from '$lib/components/BottomNav.svelte';
  import UndoToast from '$lib/components/UndoToast.svelte';
  import CreateSheets from '$lib/components/CreateSheets.svelte';
  import PullToRefresh from '$lib/components/PullToRefresh.svelte';
  import { user, me, online, trackOnline } from '$lib/client/stores';
  import { supabase } from '$lib/client/supabase';
  import { loadMe } from '$lib/client/auth';
  import { refreshAll } from '$lib/client/data';
  import { startRealtime } from '$lib/client/realtime';
  import { hydrateFromMirror, startMirrorSync } from '$lib/client/mirror';
  import { replayOutbox } from '$lib/client/outbox';
  import { hhmm } from '$lib/client/dates';

  let { children } = $props();

  const appName = PUBLIC_APP_NAME || 'Planeraren';
  const webManifestLink = pwaInfo ? pwaInfo.webManifest.linkTag : '';

  // Sökväg relativt basen (GitHub Pages serverar under en undermapp)
  const rel = $derived($page.url.pathname.slice(base.length) || '/');
  const isLogin = $derived(rel === '/login');

  // true när auth-status är avgjord (undviker login-flimmer vid uppstart)
  let authReady = $state(false);
  let loggedIn = $state(false);

  onMount(() => {
    const stopOnline = trackOnline();
    import('virtual:pwa-register').then(({ registerSW }) => {
      registerSW({ immediate: true });
    });

    // Auth-guard: reagera på sessionens livscykel.
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      loggedIn = !!session;
      authReady = true;
      const relNow = window.location.pathname.slice(base.length) || '/';
      if (!session && relNow !== '/login') void goto(`${base}/login`);
      if (session && relNow === '/login') void goto(base || '/');
    });

    return () => {
      stopOnline();
      sub.subscription.unsubscribe();
    };
  });

  // Offline-first-uppstart när inloggad: spegel → me → replay → refetch → realtid.
  $effect(() => {
    if (!loggedIn) {
      user.set(null);
      me.set(null);
      return;
    }
    let cancelled = false;
    let stopMirror = () => {};
    let stopRealtime = () => {};
    const onOnline = () => void replayThenRefresh();

    (async () => {
      await hydrateFromMirror();
      if (cancelled) return;
      stopMirror = startMirrorSync();
      await loadMe();
      await replayThenRefresh();
      if (cancelled) return;
      stopRealtime = startRealtime();
    })();

    window.addEventListener('online', onOnline);
    return () => {
      cancelled = true;
      stopMirror();
      stopRealtime();
      window.removeEventListener('online', onOnline);
    };
  });

  async function replayThenRefresh() {
    await replayOutbox();
    await refreshAll();
  }

  // Pull-to-refresh: trigga kalendersynk + hämta allt.
  async function pullRefresh() {
    try {
      await supabase.functions.invoke('caldav-sync');
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

{#if !authReady}
  <!-- kort ögonblick vid uppstart -->
{:else if isLogin}
  {@render children()}
{:else}
  <div
    class="app-shell"
    style={`--nav-active:${$user?.color ?? 'var(--accent)'};--pair-a:${$user?.color ??
      '#d4537e'};--pair-b:${$me?.partner?.color ?? '#378add'}`}
  >
    <header class="topbar">
      <span class="brand">
        <span class="pair" aria-hidden="true"><i></i><i></i></span>
        <h1>{appName}</h1>
      </span>
      <a class="icon-btn" href={`${base}/installningar`} aria-label="Inställningar">
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

    <main class="content" class:content-lock={rel === '/'}>
      <PullToRefresh onrefresh={pullRefresh}>
        {@render children()}
      </PullToRefresh>
    </main>

    <BottomNav />
    <UndoToast />
    <CreateSheets />
  </div>
{/if}
