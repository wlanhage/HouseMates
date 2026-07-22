<script lang="ts">
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { PUBLIC_APP_NAME } from '$env/static/public';
  import { loginWithUsername } from '$lib/client/auth';

  const appName = PUBLIC_APP_NAME || 'Planeraren';

  let username = $state('');
  let password = $state('');
  let error = $state('');
  let busy = $state(false);

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (!username.trim()) {
      error = 'Ange användarnamn.';
      return;
    }
    if (!password) {
      error = 'Ange lösenord.';
      return;
    }
    busy = true;
    const err = await loginWithUsername(username, password);
    busy = false;
    if (err) {
      error = err;
      password = '';
      return;
    }
    await goto(base || '/');
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
    <div class="field">
      <label for="un">Användare</label>
      <input
        id="un"
        class="input"
        type="text"
        autocomplete="username"
        autocapitalize="none"
        spellcheck="false"
        bind:value={username}
        placeholder="användarnamn"
      />
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
