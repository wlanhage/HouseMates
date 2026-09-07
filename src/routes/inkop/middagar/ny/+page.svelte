<script lang="ts">
  import { get } from 'svelte/store';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { favorites, showToast } from '$lib/client/stores';
  import { createFavorite, importRecipe } from '$lib/client/data';
  import { hostOf, itemCountLabel } from '$lib/client/text';
  import SubpageHeader from '$lib/components/SubpageHeader.svelte';

  let link = $state('');
  let fetching = $state(false);
  let name = $state('');
  let itemsText = $state('');
  let imageUrl = $state<string | null>(null);
  let sourceUrl = $state<string | null>(null);
  let busy = $state(false);

  /** En vara per rad. Skrivs allt på en rad går det bra med kommatecken. */
  function parseItems(text: string): string[] {
    const seen = new Set<string>();
    return text
      .split(text.includes('\n') ? '\n' : ',')
      .map((s) => s.trim())
      .filter((s) => s && !seen.has(s.toLowerCase()) && seen.add(s.toLowerCase()));
  }
  const itemCount = $derived(parseItems(itemsText).length);

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
    if (sourceUrl && get(favorites).some((f) => f.source_url === sourceUrl)) {
      showToast('Det receptet finns redan sparat.');
      return;
    }
    busy = true;
    const id = await createFavorite({ name, items, image_url: imageUrl, source_url: sourceUrl });
    busy = false;
    if (id) await goto(`${base}/inkop/middagar/${id}`);
  }
</script>

<svelte:head><title>Ny middag</title></svelte:head>

<SubpageHeader title="Ny middag" back="{base}/inkop/middagar" />

<form onsubmit={save}>
  <div class="card block">
    <div class="block-title">Från en receptsida</div>
    <div class="row" style="gap:0.5rem">
      <input
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
    {#if imageUrl || sourceUrl}
      <div class="preview">
        {#if imageUrl}<img src={imageUrl} alt="" />{/if}
        <div class="preview-text">
          <strong>{name || 'Recept'}</strong>
          {#if sourceUrl}<span class="muted">Från {hostOf(sourceUrl)}</span>{/if}
        </div>
      </div>
    {/if}
    <p class="muted hint">Tips: från Safari kan du dela ett recept direkt till HouseMates via genvägen.</p>
  </div>

  <div class="card block">
    <div class="field">
      <label for="fav-name">Rätt</label>
      <input id="fav-name" class="input" bind:value={name} placeholder="t.ex. Tacos" autocomplete="off" />
    </div>
    <div class="field" style="margin:0">
      <label for="fav-items">Varor, en per rad</label>
      <textarea id="fav-items" class="input" rows="8" bind:value={itemsText} placeholder={'500 g köttfärs\nTortillas\nSalsa'}></textarea>
    </div>
  </div>

  <button class="btn btn-primary btn-block cta" type="submit" disabled={busy || !name.trim() || itemCount === 0}>
    {#if busy}Sparar…{:else if itemCount > 0}Spara middag · {itemCountLabel(itemCount)}{:else}Spara middag{/if}
  </button>
</form>

<style>
  .block {
    padding: 1rem;
    margin-bottom: 1rem;
  }
  .block-title {
    font-weight: 700;
    margin-bottom: 0.6rem;
  }
  .preview {
    display: flex;
    align-items: center;
    gap: 0.7rem;
    margin-top: 0.75rem;
  }
  .preview img {
    width: 56px;
    height: 56px;
    object-fit: cover;
    border-radius: 10px;
    flex: none;
  }
  .preview-text {
    display: flex;
    flex-direction: column;
    font-size: 0.9rem;
    min-width: 0;
  }
  .preview-text strong {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .hint {
    font-size: 0.78rem;
    margin: 0.75rem 0 0;
  }
  textarea.input {
    resize: vertical;
    font: inherit;
  }
  .cta {
    padding: 0.95rem 1rem;
    font-size: 1rem;
    border-radius: 999px;
  }
</style>
