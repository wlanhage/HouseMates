<script lang="ts">
  import { goto, invalidateAll } from '$app/navigation';
  import { env } from '$env/dynamic/public';
  import { apiPost, ApiError } from '$lib/client/api';
  import type { User } from '$lib/types';

  let { data } = $props();
  const users = $derived<User[]>(data.users);
  const appName = env.PUBLIC_APP_NAME || 'Planeraren';

  let selected = $state<string | null>(null);
  let password = $state('');
  let error = $state('');
  let busy = $state(false);

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
    try {
      await apiPost('/api/auth/login', { username: selected, password });
      await invalidateAll();
      await goto('/');
    } catch (err) {
      error = err instanceof ApiError ? err.message : 'Något gick fel.';
      password = '';
    } finally {
      busy = false;
    }
  }
</script>

<svelte:head><title>{appName} – Logga in</title></svelte:head>

<div class="login-wrap">
  <div class="login-logo">
    <h1>{appName}</h1>
    <p>Er gemensamma planering</p>
  </div>

  <form onsubmit={submit}>
    <div class="user-picker">
      {#each users as u (u.id)}
        <button
          type="button"
          class="user-btn"
          class:selected={selected === u.id}
          style={`--sel:${u.color}`}
          onclick={() => (selected = u.id)}
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
