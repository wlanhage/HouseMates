<script lang="ts">
  import { me } from '$lib/client/stores';
  import { createHousehold, joinHousehold, logout } from '$lib/client/auth';

  let code = $state('');
  let error = $state('');
  let busy = $state(false);

  async function create() {
    error = '';
    busy = true;
    error = (await createHousehold()) ?? '';
    busy = false;
  }

  async function join(e: Event) {
    e.preventDefault();
    error = '';
    if (!code.trim()) {
      error = 'Skriv in koden du fått av din partner.';
      return;
    }
    busy = true;
    error = (await joinHousehold(code)) ?? '';
    busy = false;
  }
</script>

<svelte:head><title>Hushåll</title></svelte:head>

<div class="login-wrap">
  <div class="login-logo">
    <span class="pair" aria-hidden="true"><i></i><i></i></span>
    <h1>Hej{$me ? `, ${$me.user.name}` : ''}!</h1>
    <p>Listor och kalender delas med en partner i ett hushåll.</p>
  </div>

  <div class="card choice">
    <h2>Gå med i din partners hushåll</h2>
    <form onsubmit={join}>
      <div class="field">
        <label for="code">Kod från din partner</label>
        <input
          id="code"
          class="input code"
          type="text"
          autocapitalize="characters"
          autocomplete="off"
          spellcheck="false"
          maxlength="6"
          bind:value={code}
          placeholder="ABC123"
        />
      </div>
      <button class="btn btn-primary btn-block" type="submit" disabled={busy}>Gå med</button>
    </form>
  </div>

  <div class="or">eller</div>

  <div class="card choice">
    <h2>Skapa ett nytt hushåll</h2>
    <p class="muted">Du får en kod som din partner använder för att gå med.</p>
    <button class="btn btn-block" onclick={create} disabled={busy}>Skapa hushåll</button>
  </div>

  {#if error}<p class="error-text" style="text-align:center">{error}</p>{/if}

  <button class="logout" onclick={() => void logout()}>Logga ut</button>
</div>

<style>
  .choice {
    padding: 1rem;
  }
  .choice h2 {
    font-size: 1.05rem;
    margin: 0 0 0.6rem;
  }
  .choice p {
    margin: -0.2rem 0 0.8rem;
    font-size: 0.88rem;
  }
  .code {
    text-transform: uppercase;
    letter-spacing: 0.25em;
    font-weight: 700;
    text-align: center;
  }
  .or {
    text-align: center;
    color: var(--muted);
    font-size: 0.85rem;
    margin: 0.75rem 0;
  }
  .logout {
    display: block;
    margin: 1.5rem auto 0;
    border: none;
    background: none;
    color: var(--muted);
    font-size: 0.9rem;
  }
</style>
