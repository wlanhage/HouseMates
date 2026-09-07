<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import { base } from '$app/paths';
  import { favorites, shopping, showToast } from '$lib/client/stores';
  import { refreshFavorites, refreshShopping, addIngredientsToList, deleteFavorite } from '$lib/client/data';
  import { splitIngredient } from '$lib/client/ingredients';
  import { hostOf, itemCountLabel } from '$lib/client/text';

  const fav = $derived($favorites.find((f) => f.id === $page.params.id) ?? null);
  let loaded = $state(false);
  let busy = $state(false);

  // Varor som redan ligger obockade på listan – förmarkeras inte.
  const onList = $derived(
    new Set($shopping.filter((i) => !i.checked).map((i) => i.name.trim().toLowerCase()))
  );
  const alreadyOnList = (line: string): boolean =>
    onList.has(splitIngredient(line).name.toLowerCase());

  let selected = $state(new Set<string>());
  let preselected = false;

  onMount(async () => {
    await Promise.all([refreshFavorites(), refreshShopping()]);
    loaded = true;
  });

  // Förval: allt utom det som redan finns på listan (en gång, när datan finns).
  $effect(() => {
    if (fav && loaded && !preselected) {
      preselected = true;
      selected = new Set(fav.items.filter((line) => !alreadyOnList(line)));
    }
  });

  const allSelected = $derived(!!fav && fav.items.length > 0 && selected.size === fav.items.length);

  function toggle(line: string) {
    const next = new Set(selected);
    if (next.has(line)) next.delete(line);
    else next.add(line);
    selected = next;
  }

  function toggleAll() {
    if (!fav) return;
    selected = allSelected ? new Set() : new Set(fav.items);
  }

  async function addSelected() {
    if (!fav || selected.size === 0) return;
    busy = true;
    const added = await addIngredientsToList(fav.items.filter((l) => selected.has(l)));
    busy = false;
    showToast(`La till ${itemCountLabel(added)} på listan`);
    await goto(`${base}/inkop`);
  }

  async function remove() {
    if (!fav) return;
    const f = fav;
    await goto(`${base}/inkop/middagar`);
    await deleteFavorite(f);
  }
</script>

<svelte:head><title>{fav?.name ?? 'Middag'}</title></svelte:head>

{#if fav}
  <div class="hero" class:noimg={!fav.image_url}>
    {#if fav.image_url}<img src={fav.image_url} alt="" />{/if}
    <a class="hero-back" href="{base}/inkop/middagar" aria-label="Tillbaka">
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6" /></svg>
    </a>
    <div class="hero-text">
      <h2>{fav.name}</h2>
      <div class="hero-meta">
        {itemCountLabel(fav.items.length)}
        {#if fav.source_url}
          · <a href={fav.source_url} target="_blank" rel="noopener">Öppna på {hostOf(fav.source_url)} ↗</a>
        {/if}
      </div>
    </div>
  </div>

  <div class="page-body">
    {#if fav.items.length === 0}
      <div class="card empty">
        <span class="emoji">📝</span>
        Inga varor sparade för den här rätten.
      </div>
    {:else}
      <div class="sec-head">
        <span class="section-title">Ingredienser</span>
        <button class="link-btn" onclick={toggleAll}>{allSelected ? 'Avmarkera alla' : 'Välj alla'}</button>
      </div>
      <p class="muted lead">Bocka ur det ni redan har hemma.</p>
      <div class="list">
        {#each fav.items as line (line)}
          {@const on = selected.has(line)}
          {@const already = alreadyOnList(line)}
          <button class="ing" class:on aria-pressed={on} onclick={() => toggle(line)}>
            <span class="box" class:on>
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12 5 5L20 7" /></svg>
            </span>
            <span class="ing-text">
              <span class:dim={already && !on}>{line}</span>
              {#if already}<small>finns redan på listan</small>{/if}
            </span>
          </button>
        {/each}
      </div>
    {/if}

    {#if fav.items.length > 0}
      <!-- sticky (inte fixed): pull-to-refresh-omslaget har en transform som
           skulle göra fixed relativt omslaget istället för skärmen -->
      <div class="actionbar">
        <button class="btn btn-primary cta" disabled={busy || selected.size === 0} onclick={addSelected}>
          {#if busy}Lägger till…{:else if selected.size === 0}Välj varor att lägga till{:else}Lägg {itemCountLabel(selected.size)} på listan{/if}
        </button>
      </div>
    {/if}

    <button class="danger-link" onclick={remove}>Ta bort från Våra middagar</button>
  </div>
{:else if loaded}
  <div class="card empty">
    <span class="emoji">🤷</span>
    Den här middagen finns inte längre.
    <a class="btn first-btn" href="{base}/inkop/middagar">Till Våra middagar</a>
  </div>
{:else}
  <p class="muted" style="text-align:center;padding:2rem 0">Laddar…</p>
{/if}

<style>
  .hero {
    position: relative;
    margin: -0.75rem -1.1rem 1rem;
    height: 38vh;
    min-height: 220px;
    max-height: 340px;
    overflow: hidden;
    background: linear-gradient(135deg, var(--accent), color-mix(in srgb, var(--accent) 55%, #000));
  }
  .hero img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    display: block;
  }
  .hero.noimg::before {
    content: '🍽️';
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 4rem;
    opacity: 0.55;
  }
  .hero::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(to top, rgba(0, 0, 0, 0.74) 0%, rgba(0, 0, 0, 0.28) 45%, rgba(0, 0, 0, 0) 75%);
  }
  .hero-back {
    position: absolute;
    top: 0.65rem;
    left: 0.85rem;
    z-index: 2;
    width: 38px;
    height: 38px;
    border-radius: 999px;
    background: rgba(0, 0, 0, 0.38);
    color: #fff;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    backdrop-filter: blur(6px);
    -webkit-backdrop-filter: blur(6px);
  }
  .hero-text {
    position: absolute;
    left: 1.1rem;
    right: 1.1rem;
    bottom: 0.95rem;
    z-index: 2;
    color: #fff;
  }
  .hero-text h2 {
    margin: 0 0 0.25rem;
    font-size: 1.5rem;
    font-weight: 800;
    line-height: 1.15;
    text-shadow: 0 1px 10px rgba(0, 0, 0, 0.45);
  }
  .hero-meta {
    font-size: 0.85rem;
    opacity: 0.94;
  }
  .hero-meta a {
    color: #fff;
    font-weight: 600;
  }
  .page-body {
    padding-bottom: 1rem;
  }
  .sec-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.2rem;
  }
  .sec-head .section-title {
    margin: 0;
  }
  .link-btn {
    border: none;
    background: none;
    color: var(--accent);
    font-weight: 700;
    font-size: 0.85rem;
    padding: 0.3rem 0;
  }
  .lead {
    margin: 0 0 0.7rem;
    font-size: 0.85rem;
  }
  .ing {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    text-align: left;
    padding: 0.8rem 0.9rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
    color: var(--text);
    font-size: 0.95rem;
    transition: background 0.15s, border-color 0.15s;
  }
  .ing.on {
    border-color: color-mix(in srgb, var(--accent) 45%, var(--border));
    background: color-mix(in srgb, var(--accent) 7%, var(--surface));
  }
  .box {
    width: 24px;
    height: 24px;
    flex: none;
    border-radius: 999px;
    border: 2px solid var(--border);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: transparent;
    transition: background 0.15s, border-color 0.15s, color 0.15s;
  }
  .box.on {
    background: var(--accent);
    border-color: var(--accent);
    color: var(--on-accent);
  }
  .ing-text {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    line-height: 1.3;
  }
  .ing-text small {
    color: var(--muted);
    font-size: 0.75rem;
  }
  .dim {
    color: var(--muted);
  }
  .danger-link {
    display: block;
    margin: 1.75rem auto 0;
    border: none;
    background: none;
    color: var(--danger);
    font-weight: 600;
    font-size: 0.9rem;
  }
  .actionbar {
    position: sticky;
    bottom: calc(var(--nav-h) + var(--safe-b) + 2.6rem);
    z-index: 15;
    padding: 0.75rem 0 0.25rem;
  }
  .cta {
    display: flex;
    width: 100%;
    max-width: 640px;
    margin: 0 auto;
    padding: 0.95rem 1rem;
    font-size: 1rem;
    border-radius: 999px;
    box-shadow: var(--shadow-lg);
  }
  .first-btn {
    display: flex;
    width: fit-content;
    margin: 1.1rem auto 0;
    text-decoration: none;
  }
</style>
