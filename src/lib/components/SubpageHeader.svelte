<script lang="ts">
  import type { Snippet } from 'svelte';

  /** Rubrik för undersidor: tillbaka-knapp, titel och valfri knapp till höger. */
  let { title, back, right }: { title: string; back: string; right?: Snippet } = $props();
</script>

<header class="subhead">
  <a class="round-btn" href={back} aria-label="Tillbaka">
    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6" /></svg>
  </a>
  <h2>{title}</h2>
  {#if right}
    {@render right()}
  {:else}
    <span class="round-spacer"></span>
  {/if}
</header>

<style>
  .subhead {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin: 0.15rem 0 1rem;
  }
  .subhead h2 {
    flex: 1;
    margin: 0;
    font-size: 1.3rem;
    font-weight: 800;
    text-align: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .subhead :global(.round-btn) {
    width: 40px;
    height: 40px;
    flex: none;
    border-radius: 999px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    background: var(--surface);
    border: 1px solid var(--border);
    box-shadow: var(--shadow);
    color: var(--text);
    text-decoration: none;
    transition: transform 0.08s;
  }
  .subhead :global(.round-btn:active) {
    transform: scale(0.94);
  }
  .round-spacer {
    width: 40px;
    flex: none;
  }
</style>
