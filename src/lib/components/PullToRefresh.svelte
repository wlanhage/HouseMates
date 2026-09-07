<script lang="ts">
  import type { Snippet } from 'svelte';

  let { onrefresh, children }: { onrefresh: () => Promise<void>; children: Snippet } = $props();

  let pull = $state(0);
  let refreshing = $state(false);
  let active = $state(false);
  let startY = 0;

  function down(e: TouchEvent) {
    // Ytor med egna drag-gester (t.ex. Hem-splitten) opt:ar ut via data-no-ptr.
    if (e.target instanceof Element && e.target.closest('[data-no-ptr]')) return;
    if (window.scrollY <= 0 && !refreshing) {
      startY = e.touches[0].clientY;
      active = true;
    }
  }
  function move(e: TouchEvent) {
    if (!active) return;
    const d = e.touches[0].clientY - startY;
    if (d > 0 && window.scrollY <= 0) pull = Math.min(80, d * 0.5);
    else {
      active = false;
      pull = 0;
    }
  }
  async function up() {
    if (!active) return;
    active = false;
    if (pull > 45) {
      refreshing = true;
      pull = 40;
      try {
        await onrefresh();
      } finally {
        refreshing = false;
        pull = 0;
      }
    } else {
      pull = 0;
    }
  }
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div ontouchstart={down} ontouchmove={move} ontouchend={up}>
  {#if pull > 0 || refreshing}
    <div class="ptr" style={`height:${refreshing ? 40 : pull}px`}>
      {refreshing ? 'Uppdaterar…' : pull > 45 ? 'Släpp för att uppdatera' : 'Dra för att uppdatera'}
    </div>
  {/if}
  <!-- transform bara under dragning: en permanent transform gör position:fixed
       i sidorna (sheets, dialoger) relativ till omslaget istället för skärmen -->
  <div style={pull || refreshing ? `transform:translateY(${pull}px);transition:${active ? 'none' : 'transform 0.2s'}` : ''}>
    {@render children()}
  </div>
</div>

<style>
  .ptr {
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.8rem;
    color: var(--muted);
    overflow: hidden;
  }
</style>
