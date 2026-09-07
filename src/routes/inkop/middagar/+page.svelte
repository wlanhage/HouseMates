<script lang="ts">
  import { onMount } from 'svelte';
  import { base } from '$app/paths';
  import { favorites } from '$lib/client/stores';
  import { refreshFavorites } from '$lib/client/data';
  import { hostOf, itemCountLabel } from '$lib/client/text';
  import SubpageHeader from '$lib/components/SubpageHeader.svelte';

  onMount(() => {
    void refreshFavorites();
  });
</script>

<svelte:head><title>Våra middagar</title></svelte:head>

<SubpageHeader title="Våra middagar" back="{base}/inkop">
  {#snippet right()}
    <a class="round-btn accent" href="{base}/inkop/middagar/ny" aria-label="Ny middag">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg>
    </a>
  {/snippet}
</SubpageHeader>

{#if $favorites.length === 0}
  <div class="card empty">
    <span class="emoji">🍽️</span>
    Inga middagar sparade än.<br />
    Spara rätter ni gillar, så lägger ett tryck varorna på inköpslistan.
    <a class="btn btn-primary first-btn" href="{base}/inkop/middagar/ny">Lägg till den första</a>
  </div>
{:else}
  <div class="grid">
    {#each $favorites as f (f.id)}
      <a class="dish" href="{base}/inkop/middagar/{f.id}">
        {#if f.image_url}
          <img src={f.image_url} alt="" loading="lazy" />
        {:else}
          <div class="ph" aria-hidden="true">🍽️</div>
        {/if}
        <div class="dish-body">
          <div class="dish-name">{f.name}</div>
          <div class="dish-meta">
            {itemCountLabel(f.items.length)}{f.source_url ? ` · ${hostOf(f.source_url)}` : ''}
          </div>
        </div>
      </a>
    {/each}
  </div>
{/if}

<style>
  :global(.round-btn.accent) {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--on-accent);
  }
  .first-btn {
    display: flex;
    width: fit-content;
    margin: 1.1rem auto 0;
    text-decoration: none;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.8rem;
  }
  .dish {
    display: block;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    overflow: hidden;
    box-shadow: var(--shadow);
    color: var(--text);
    text-decoration: none;
    transition: transform 0.08s;
  }
  .dish:active {
    transform: scale(0.97);
  }
  .dish img,
  .ph {
    display: block;
    width: 100%;
    aspect-ratio: 4 / 3;
    object-fit: cover;
    background: var(--surface-2);
  }
  .ph {
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 2.4rem;
    background: linear-gradient(135deg, color-mix(in srgb, var(--accent) 22%, var(--surface-2)), var(--surface-2));
  }
  .dish-body {
    padding: 0.6rem 0.75rem 0.8rem;
  }
  .dish-name {
    font-weight: 700;
    font-size: 0.95rem;
    line-height: 1.25;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .dish-meta {
    margin-top: 0.3rem;
    font-size: 0.76rem;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
