<script lang="ts">
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { PUBLIC_APP_NAME } from '$env/static/public';
  import { signup } from '$lib/client/auth';

  const appName = PUBLIC_APP_NAME || 'Planeraren';

  let name = $state('');
  let username = $state('');
  let password = $state('');
  let error = $state('');
  let busy = $state(false);

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (!name.trim() || !username.trim()) {
      error = 'Fyll i namn och användarnamn.';
      return;
    }
    if (password.length < 8) {
      error = 'Lösenordet måste ha minst 8 tecken.';
      return;
    }
    busy = true;
    const err = await signup(username, name, password);
    busy = false;
    if (err) {
      error = err;
      return;
    }
    await goto(`${base}/hushall`);
  }
</script>

<svelte:head><title>{appName} – Skapa konto</title></svelte:head>

<div class="login-wrap">
  <div class="login-logo">
    <span class="pair" aria-hidden="true"><i></i><i></i></span>
    <h1>Skapa konto</h1>
    <p>Sedan skapar du ett hushåll eller går med i din partners.</p>
  </div>

  <form onsubmit={submit}>
    <div class="field">
      <label for="nm">Ditt namn</label>
      <input id="nm" class="input" type="text" autocomplete="given-name" bind:value={name} placeholder="t.ex. Sara" />
    </div>
    <div class="field">
      <label for="un">Användarnamn</label>
      <input
        id="un"
        class="input"
        type="text"
        autocomplete="username"
        autocapitalize="none"
        spellcheck="false"
        bind:value={username}
        placeholder="a–z, 0–9, - och _"
      />
    </div>
    <div class="field">
      <label for="pw">Lösenord</label>
      <input id="pw" class="input" type="password" autocomplete="new-password" bind:value={password} placeholder="minst 8 tecken" />
    </div>

    <p class="error-text">{error}</p>

    <button class="btn btn-primary btn-block" type="submit" disabled={busy}>
      {busy ? 'Skapar konto…' : 'Skapa konto'}
    </button>
  </form>

  <p class="switch">Har du redan ett konto? <a href="{base}/login">Logga in</a></p>
</div>

<style>
  .switch {
    text-align: center;
    margin-top: 1.25rem;
    color: var(--muted);
    font-size: 0.9rem;
  }
  .switch a {
    color: var(--accent);
    font-weight: 700;
  }
</style>
