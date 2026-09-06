<script lang="ts">
  import { onMount } from 'svelte';
  import { listFavorites, createFavorite, deleteFavorite, addFavoriteToList } from '$lib/client/data';
  import type { Favorite } from '$lib/types';

  /** Favoritmiddagar: se, lägga till, och skicka varorna till inköpslistan. */
  let { onclose }: { onclose: () => void } = $props();

  let favorites = $state<Favorite[]>([]);
  let loading = $state(true);
  let expanded = $state<string | null>(null);
  let adding = $state(false);
  let name = $state('');
  let itemsText = $state('');
  let busy = $state(false);
  let nameField: HTMLInputElement | undefined = $state();

  onMount(load);

  async function load() {
    favorites = await listFavorites();
    loading = false;
  }

  function startAdd() {
    adding = true;
    name = '';
    itemsText = '';
    setTimeout(() => nameField?.focus(), 30);
  }

  /** En vara per rad (kommatecken funkar också). */
  function parseItems(text: string): string[] {
    const seen = new Set<string>();
    return text
      .split(/[\n,]/)
      .map((s) => s.trim())
      .filter((s) => s && !seen.has(s.toLowerCase()) && seen.add(s.toLowerCase()));
  }

  async function save(e: Event) {
    e.preventDefault();
    const items = parseItems(itemsText);
    if (!name.trim() || items.length === 0) return;
    busy = true;
    const ok = await createFavorite(name, items);
    busy = false;
    if (!ok) return;
    adding = false;
    await load();
  }

  async function addToList(f: Favorite) {
    busy = true;
    await addFavoriteToList(f);
    busy = false;
    onclose();
  }

  async function remove(f: Favorite) {
    favorites = favorites.filter((x) => x.id !== f.id);
    await deleteFavorite(f);
  }
</script>

<svelte:window
  onkeydown={(e) => {
    if (e.key === 'Escape') onclose();
  }}
/>

<div class="scrim">
  <button class="scrim-bg" aria-label="Stäng" onclick={onclose}></button>
  <div class="sheet" role="dialog" aria-modal="true" aria-label="Favoritmiddagar">
    <div class="sheet-handle"></div>
    <div class="head">
      <h3>Våra middagar</h3>
      {#if !adding}
        <button class="btn small" onclick={startAdd}>+ Ny</button>
      {/if}
    </div>

    <div class="body">
      {#if adding}
        <form onsubmit={save} class="add-form">
          <div class="field">
            <label for="fav-name">Rätt</label>
            <input id="fav-name" bind:this={nameField} class="input" bind:value={name} placeholder="t.ex. Tacos" autocomplete="off" />
          </div>
          <div class="field">
            <label for="fav-items">Varor (en per rad)</label>
            <textarea id="fav-items" class="input" rows="5" bind:value={itemsText} placeholder={'Köttfärs\nTortillas\nSalsa'}></textarea>
          </div>
          <div class="row" style="gap:0.5rem">
            <button class="btn" type="button" style="flex:1" onclick={() => (adding = false)}>Avbryt</button>
            <button class="btn btn-primary" type="submit" style="flex:1" disabled={busy || !name.trim() || parseItems(itemsText).length === 0}>Spara</button>
          </div>
        </form>
      {/if}

      {#if loading}
        <p class="muted center">Laddar…</p>
      {:else if favorites.length === 0 && !adding}
        <p class="muted center">
          Inga favoriter än. Spara middagar ni gillar, så lägger ett tryck alla varor på listan.
        </p>
      {/if}

      {#each favorites as f (f.id)}
        <div class="fav" class:open={expanded === f.id}>
          <button class="fav-row" onclick={() => (expanded = expanded === f.id ? null : f.id)}>
            <span class="fav-name">{f.name}</span>
            <span class="muted count">{f.items.length === 1 ? '1 vara' : `${f.items.length} varor`}</span>
            <svg class="chev" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
          </button>
          {#if expanded === f.id}
            <div class="fav-body">
              <ul>
                {#each f.items as item (item)}<li>{item}</li>{/each}
              </ul>
              <div class="row" style="gap:0.5rem">
                <button class="btn btn-danger" onclick={() => void remove(f)}>Ta bort</button>
                <button class="btn btn-primary" style="flex:1" disabled={busy} onclick={() => void addToList(f)}>
                  Lägg på listan
                </button>
              </div>
            </div>
          {/if}
        </div>
      {/each}
    </div>
  </div>
</div>

<style>
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 0.5rem 0.5rem;
  }
  .head h3 {
    margin: 0;
  }
  .btn.small {
    padding: 0.35rem 0.8rem;
    font-size: 0.85rem;
  }
  .body {
    max-height: 62vh;
    overflow-y: auto;
    padding: 0 0.5rem 0.5rem;
  }
  .add-form {
    padding: 0.25rem 0 0.75rem;
    border-bottom: 1px solid var(--border);
    margin-bottom: 0.75rem;
  }
  textarea.input {
    resize: vertical;
    font: inherit;
  }
  .center {
    text-align: center;
    padding: 0.75rem 0;
  }
  .fav {
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
    margin-bottom: 0.5rem;
    overflow: hidden;
  }
  .fav-row {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    width: 100%;
    border: none;
    background: transparent;
    color: var(--text);
    padding: 0.85rem 0.9rem;
    text-align: left;
    font-size: 1rem;
  }
  .fav-name {
    flex: 1;
    font-weight: 600;
  }
  .count {
    font-size: 0.8rem;
  }
  .chev {
    color: var(--muted);
    transition: transform 0.15s;
  }
  .fav.open .chev {
    transform: rotate(90deg);
  }
  .fav-body {
    padding: 0 0.9rem 0.85rem;
  }
  .fav-body ul {
    margin: 0 0 0.75rem;
    padding-left: 1.2rem;
    color: var(--muted);
    font-size: 0.9rem;
    line-height: 1.5;
  }
</style>
