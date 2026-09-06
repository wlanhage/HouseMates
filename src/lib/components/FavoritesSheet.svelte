<script lang="ts">
  import { onMount } from 'svelte';
  import {
    listFavorites,
    createFavorite,
    deleteFavorite,
    addFavoriteToList,
    addIngredientToList,
    importRecipe
  } from '$lib/client/data';
  import { showToast } from '$lib/client/stores';
  import type { Favorite } from '$lib/types';

  /** Favoritmiddagar: se, lägga till (manuellt eller från receptlänk) och skicka varor till listan. */
  let { onclose }: { onclose: () => void } = $props();

  let favorites = $state<Favorite[]>([]);
  let loading = $state(true);
  let expanded = $state<string | null>(null);
  let busy = $state(false);

  // Nytt-formulär
  let adding = $state(false);
  let link = $state('');
  let fetching = $state(false);
  let name = $state('');
  let itemsText = $state('');
  let imageUrl = $state<string | null>(null);
  let sourceUrl = $state<string | null>(null);
  let linkField: HTMLInputElement | undefined = $state();

  // Ingredienser som lagts på listan i den här sessionen (för ✓-markering)
  let added = $state(new Set<string>());

  onMount(load);

  async function load() {
    favorites = await listFavorites();
    loading = false;
  }

  function startAdd() {
    adding = true;
    link = '';
    name = '';
    itemsText = '';
    imageUrl = null;
    sourceUrl = null;
    setTimeout(() => linkField?.focus(), 30);
  }

  /** En vara per rad (kommatecken funkar också). */
  function parseItems(text: string): string[] {
    const seen = new Set<string>();
    return text
      .split(/[\n,]/)
      .map((s) => s.trim())
      .filter((s) => s && !seen.has(s.toLowerCase()) && seen.add(s.toLowerCase()));
  }

  async function fetchRecipe() {
    const url = link.trim();
    if (!url) return;
    fetching = true;
    const recipe = await importRecipe(url);
    fetching = false;
    if (!recipe) return;
    name = recipe.name;
    itemsText = recipe.items.join('\n');
    imageUrl = recipe.image_url;
    sourceUrl = recipe.source_url;
    if (recipe.items.length === 0) showToast('Hittade inga ingredienser – fyll i dem själv.');
  }

  async function save(e: Event) {
    e.preventDefault();
    const items = parseItems(itemsText);
    if (!name.trim() || items.length === 0) return;
    if (sourceUrl && favorites.some((f) => f.source_url === sourceUrl)) {
      showToast('Det receptet finns redan sparat.');
      return;
    }
    busy = true;
    const ok = await createFavorite({ name, items, image_url: imageUrl, source_url: sourceUrl });
    busy = false;
    if (!ok) return;
    adding = false;
    await load();
  }

  async function addAll(f: Favorite) {
    busy = true;
    await addFavoriteToList(f);
    busy = false;
    onclose();
  }

  async function addOne(f: Favorite, line: string) {
    const key = f.id + '\n' + line;
    if (await addIngredientToList(line)) added = new Set(added).add(key);
  }

  async function remove(f: Favorite) {
    favorites = favorites.filter((x) => x.id !== f.id);
    await deleteFavorite(f);
  }

  const hostOf = (url: string): string => {
    try {
      return new URL(url).hostname.replace(/^www\./, '');
    } catch {
      return url;
    }
  };
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
            <label for="fav-link">Från en receptsida (valfritt)</label>
            <div class="row" style="gap:0.5rem">
              <input
                id="fav-link"
                bind:this={linkField}
                class="input"
                type="url"
                inputmode="url"
                bind:value={link}
                placeholder="Klistra in länken…"
                autocomplete="off"
                onkeydown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    void fetchRecipe();
                  }
                }}
              />
              <button class="btn" type="button" disabled={fetching || !link.trim()} onclick={fetchRecipe}>
                {fetching ? 'Hämtar…' : 'Hämta'}
              </button>
            </div>
          </div>
          {#if imageUrl || sourceUrl}
            <div class="preview">
              {#if imageUrl}<img src={imageUrl} alt="" />{/if}
              {#if sourceUrl}<span class="muted">Från {hostOf(sourceUrl)}</span>{/if}
            </div>
          {/if}
          <div class="field">
            <label for="fav-name">Rätt</label>
            <input id="fav-name" class="input" bind:value={name} placeholder="t.ex. Tacos" autocomplete="off" />
          </div>
          <div class="field">
            <label for="fav-items">Varor (en per rad)</label>
            <textarea id="fav-items" class="input" rows="6" bind:value={itemsText} placeholder={'500 g köttfärs\nTortillas\nSalsa'}></textarea>
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
          Inga favoriter än. Spara middagar ni gillar (eller klistra in ett recept), så lägger ett tryck varorna på listan.
        </p>
      {/if}

      {#each favorites as f (f.id)}
        <div class="fav" class:open={expanded === f.id}>
          <button class="fav-row" onclick={() => (expanded = expanded === f.id ? null : f.id)}>
            {#if f.image_url}
              <img class="thumb" src={f.image_url} alt="" loading="lazy" />
            {:else}
              <span class="thumb placeholder">🍽️</span>
            {/if}
            <span class="fav-main">
              <span class="fav-name">{f.name}</span>
              <span class="muted count">
                {f.items.length === 1 ? '1 vara' : `${f.items.length} varor`}
                {#if f.source_url} · {hostOf(f.source_url)}{/if}
              </span>
            </span>
            <svg class="chev" viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
          </button>
          {#if expanded === f.id}
            <div class="fav-body">
              <ul class="ingredients">
                {#each f.items as line (line)}
                  {@const done = added.has(f.id + '\n' + line)}
                  <li>
                    <span class="line" class:done>{line}</span>
                    <button class="add-one" class:done aria-label={`Lägg ${line} på listan`} disabled={done} onclick={() => void addOne(f, line)}>
                      {#if done}
                        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5L20 7" /></svg>
                      {:else}
                        <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg>
                      {/if}
                    </button>
                  </li>
                {/each}
              </ul>
              {#if f.items.length === 0}
                <p class="muted" style="font-size:0.85rem;margin:0 0 0.75rem">Inga varor sparade än.</p>
              {/if}
              <div class="row" style="gap:0.5rem">
                <button class="btn btn-danger" onclick={() => void remove(f)}>Ta bort</button>
                {#if f.source_url}
                  <a class="btn" href={f.source_url} target="_blank" rel="noopener">Öppna receptet</a>
                {/if}
                <button class="btn btn-primary" style="flex:1" disabled={busy || f.items.length === 0} onclick={() => void addAll(f)}>
                  Lägg allt på listan
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
    max-height: 68vh;
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
  .preview {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    margin: -0.25rem 0 0.75rem;
    font-size: 0.85rem;
  }
  .preview img {
    width: 56px;
    height: 56px;
    object-fit: cover;
    border-radius: 10px;
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
    gap: 0.7rem;
    width: 100%;
    border: none;
    background: transparent;
    color: var(--text);
    padding: 0.6rem 0.9rem 0.6rem 0.6rem;
    text-align: left;
    font-size: 1rem;
  }
  .thumb {
    width: 44px;
    height: 44px;
    border-radius: 10px;
    object-fit: cover;
    flex: none;
    background: var(--surface-2);
  }
  .thumb.placeholder {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-size: 1.3rem;
  }
  .fav-main {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }
  .fav-name {
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .count {
    font-size: 0.8rem;
  }
  .chev {
    color: var(--muted);
    transition: transform 0.15s;
    flex: none;
  }
  .fav.open .chev {
    transform: rotate(90deg);
  }
  .fav-body {
    padding: 0 0.9rem 0.85rem;
  }
  .ingredients {
    list-style: none;
    margin: 0 0 0.75rem;
    padding: 0;
  }
  .ingredients li {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.3rem 0;
    border-top: 1px solid var(--border);
    font-size: 0.92rem;
  }
  .ingredients li:first-child {
    border-top: none;
  }
  .line {
    flex: 1;
    min-width: 0;
  }
  .line.done {
    color: var(--muted);
  }
  .add-one {
    flex: none;
    width: 30px;
    height: 30px;
    border-radius: 50%;
    border: 1.5px solid var(--border);
    background: var(--surface);
    color: var(--accent);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s, color 0.15s, border-color 0.15s;
  }
  .add-one.done {
    background: var(--ok);
    border-color: var(--ok);
    color: #fff;
  }
  a.btn {
    text-decoration: none;
    display: inline-flex;
    align-items: center;
  }
</style>
