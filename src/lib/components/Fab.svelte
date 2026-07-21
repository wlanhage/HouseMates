<script lang="ts">
  import { online, createKind } from '$lib/client/stores';

  let open = $state(false);

  function choose(kind: 'event' | 'shopping' | 'todo') {
    open = false;
    createKind.set(kind);
  }
</script>

<svelte:window
  onkeydown={(e) => {
    if (open && e.key === 'Escape') open = false;
  }}
/>

<button class="fab" aria-label="Lägg till" onclick={() => (open = true)}>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round">
    <path d="M12 5v14M5 12h14" />
  </svg>
</button>

{#if open}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={() => (open = false)}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Skapa nytt">
      <div class="sheet-handle"></div>
      <button class="sheet-item" disabled={!$online} onclick={() => choose('event')}>
        <span class="sheet-icon">📅</span>
        <span>
          Nytt event
          {#if !$online}<span class="muted" style="font-weight:400"> · kräver anslutning</span>{/if}
        </span>
      </button>
      <button class="sheet-item" onclick={() => choose('shopping')}>
        <span class="sheet-icon">🛒</span>
        <span>Ny vara</span>
      </button>
      <button class="sheet-item" onclick={() => choose('todo')}>
        <span class="sheet-icon">✅</span>
        <span>Ny uppgift</span>
      </button>
    </div>
  </div>
{/if}
