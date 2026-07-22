<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { PUBLIC_APP_NAME } from '$env/static/public';
  import { fetchProfiles, login } from '$lib/client/auth';
  import type { ProfileRow } from '$lib/client/supabase';

  const appName = PUBLIC_APP_NAME || 'Planeraren';

  let users = $state<ProfileRow[]>([]);
  let selected = $state<ProfileRow | null>(null);
  let password = $state('');
  let error = $state('');
  let busy = $state(false);

  onMount(async () => {
    try {
      users = await fetchProfiles();
    } catch {
      error = 'Kunde inte hämta användare – kontrollera anslutningen.';
    }
  });

  function initials(name: string): string {
    return name.trim().charAt(0).toUpperCase();
  }

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (!selected) {
      error = 'Välj vem du är.';
      return;
    }
    if (!password) {
      error = 'Ange lösenord.';
      return;
    }
    busy = true;
    const err = await login(selected.email, password);
    busy = false;
    if (err) {
      error = err;
      password = '';
      return;
    }
    await goto('/');
  }
</script>

<svelte:head><title>{appName} – Logga in</title></svelte:head>

<div class="login-wrap">
  <div class="login-logo">
    <span class="pair" aria-hidden="true"><i></i><i></i></span>
    <h1>{appName}</h1>
    <p>Er gemensamma planering</p>
  </div>

  <form onsubmit={submit}>
    <div class="user-picker">
      {#each users as u (u.username)}
        <button
          type="button"
          class="user-btn"
          class:selected={selected?.username === u.username}
          style={`--sel:${u.color}`}
          onclick={() => (selected = u)}
        >
          <span class="avatar" style={`background:${u.color}`}>{initials(u.name)}</span>
          {u.name}
        </button>
      {/each}
    </div>

    <div class="field">
      <label for="pw">Lösenord</label>
      <input
        id="pw"
        class="input"
        type="password"
        autocomplete="current-password"
        bind:value={password}
        placeholder="••••••••"
      />
    </div>

    <p class="error-text">{error}</p>

    <button class="btn btn-primary btn-block" type="submit" disabled={busy}>
      {busy ? 'Loggar in…' : 'Logga in'}
    </button>
  </form>
</div>
