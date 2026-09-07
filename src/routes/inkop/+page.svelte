<script lang="ts">
  import { onMount, tick } from 'svelte';
  import { crossfade, fly } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import { shopping } from '$lib/client/stores';
  import { people, colorOf, initialOf } from '$lib/client/people';
  import {
    refreshShopping,
    createShopping,
    setChecked,
    deleteShopping,
    archiveChecked,
    suggestShopping
  } from '$lib/client/data';
  import SwipeRow from '$lib/components/SwipeRow.svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import { base } from '$app/paths';
  import type { ShoppingItem } from '$lib/types';

  let text = $state('');
  let suggestions = $state<{ name: string }[]>([]);
  let showSuggest = $state(false);
  let inputEl: HTMLInputElement | undefined = $state();
  let sugTimer: ReturnType<typeof setTimeout> | undefined;

  const active = $derived($shopping.filter((i) => !i.checked));
  const checked = $derived($shopping.filter((i) => i.checked));

  // ── Avbockningsanimation ──────────────────────────────────
  // 1) bocken ritas i rutan (CSS), 2) raden flyger till sin nya
  // plats i andra sektionen (crossfade send/receive).
  const [send, receive] = crossfade({
    duration: 420,
    easing: cubicOut,
    fallback: (node) => fly(node, { y: 40, duration: 300, easing: cubicOut })
  });

  let pending = $state(new Set<string>());
  const DRAW_MS = 480;

  function handleCheck(item: ShoppingItem) {
    if (pending.has(item.id)) return;
    pending = new Set(pending).add(item.id);
    setTimeout(() => {
      pending = new Set([...pending].filter((id) => id !== item.id));
      void setChecked(item, true);
    }, DRAW_MS);
  }

  onMount(() => {
    void refreshShopping();
  });

  function loadSuggest(q: string) {
    clearTimeout(sugTimer);
    sugTimer = setTimeout(async () => {
      suggestions = await suggestShopping(q);
    }, 120);
  }

  function onFocus() {
    showSuggest = true;
    loadSuggest(text);
  }
  function onInput() {
    showSuggest = true;
    loadSuggest(text);
  }

  async function add(name = text) {
    const n = name.trim();
    if (!n) return;
    await createShopping(n);
    text = '';
    suggestions = [];
    await tick();
    inputEl?.focus();
    loadSuggest('');
  }

  function submit(e: Event) {
    e.preventDefault();
    void add();
  }

  // Dölj förslag vid klick utanför.
  function onBlur() {
    setTimeout(() => (showSuggest = false), 150);
  }

  const nameChip = (i: ShoppingItem) =>
    i.checked ? (i.checked_by ?? i.created_by) : i.created_by;
</script>

<svelte:head><title>Inköp</title></svelte:head>

<div class="title-row">
  <h2 class="page-title" style="margin:0;flex:1">Inköp</h2>
  <a class="icon-btn fav-btn" href="{base}/inkop/middagar" aria-label="Våra middagar">
    <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
      <path d="M6 3v6a2.5 2.5 0 0 0 5 0V3M8.5 3v18" />
      <path d="M18 3c-2.2 2.2-3 5-3 8 0 1.4 1.2 2.5 3 2.5V21" />
    </svg>
  </a>
</div>

<form onsubmit={submit} style="position:relative;margin-bottom:1rem">
  <div class="row" style="gap:0.5rem">
    <input
      bind:this={inputEl}
      bind:value={text}
      class="input"
      placeholder="Lägg till vara…"
      autocomplete="off"
      oninput={onInput}
      onfocus={onFocus}
      onblur={onBlur}
    />
    <button class="btn btn-primary" type="submit" aria-label="Lägg till" disabled={!text.trim()}>
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M12 5v14M5 12h14" /></svg>
    </button>
  </div>

  {#if showSuggest && suggestions.length}
    <div class="chips">
      {#each suggestions as s (s.name)}
        <button type="button" class="chip" onpointerdown={(e) => { e.preventDefault(); void add(s.name); }}>
          {s.name}
        </button>
      {/each}
    </div>
  {/if}
</form>

{#if active.length === 0 && checked.length === 0}
  <div class="card empty">
    <span class="emoji">🛒</span>
    Listan är tom. Lägg till något ovan.
  </div>
{/if}

{#if active.length}
  <div class="list">
    {#each active as item (item.id)}
      <div
        class="anim-wrap"
        in:receive={{ key: item.id }}
        out:send={{ key: item.id }}
        animate:flip={{ duration: 300, easing: cubicOut }}
      >
        <SwipeRow ontap={() => handleCheck(item)} ondelete={() => void deleteShopping(item)}>
          <div class="shop-row" class:checking={pending.has(item.id)}>
            <span class="checkbox" data-tap class:drawing={pending.has(item.id)}>
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
            </span>
            <span class="shop-name">
              {item.name}
              {#if item.qty}<span class="muted"> · {item.qty}</span>{/if}
            </span>
            <span class="dot" style={`background:${colorOf($people, nameChip(item))}`}></span>
          </div>
        </SwipeRow>
      </div>
    {/each}
  </div>
{/if}

{#if checked.length}
  <div class="row" style="margin:1.25rem 0 0.5rem">
    <div class="section-title" style="margin:0">Avklarade · {checked.length}</div>
    <div class="spacer"></div>
    <button class="btn" style="padding:0.35rem 0.7rem;font-size:0.85rem" onclick={() => void archiveChecked()}>
      Töm avklarade
    </button>
  </div>
  <div class="list">
    {#each checked as item (item.id)}
      <div
        class="anim-wrap"
        in:receive={{ key: item.id }}
        out:send={{ key: item.id }}
        animate:flip={{ duration: 300, easing: cubicOut }}
      >
        <SwipeRow ontap={() => void setChecked(item, false)} ondelete={() => void deleteShopping(item)}>
          <div class="shop-row done">
            <span class="checkbox on" data-tap>
              <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
            </span>
            <span class="shop-name">
              {item.name}
              {#if item.qty}<span class="muted"> · {item.qty}</span>{/if}
            </span>
            <Avatar color={colorOf($people, nameChip(item))} initial={initialOf($people, nameChip(item))} size={22} />
          </div>
        </SwipeRow>
      </div>
    {/each}
  </div>
{/if}

<style>
  .title-row {
    display: flex;
    align-items: center;
    margin: 0.35rem 0 1rem;
  }
  .fav-btn {
    color: var(--accent);
    background: var(--bg-tint);
  }
  .chips {
    position: absolute;
    left: 0;
    right: 0;
    top: calc(100% + 0.4rem);
    z-index: 10;
    display: flex;
    gap: 0.4rem;
    overflow-x: auto;
    padding: 0.5rem;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    box-shadow: var(--shadow);
    scrollbar-width: none;
  }
  .chips::-webkit-scrollbar {
    display: none;
  }
  .chip {
    flex: none;
    border: 1px solid var(--border);
    background: var(--surface-2);
    color: var(--text);
    border-radius: 999px;
    padding: 0.4rem 0.8rem;
    font-size: 0.85rem;
    font-weight: 650;
    white-space: nowrap;
    transition: background 0.12s;
  }
  .chip:active {
    background: color-mix(in srgb, var(--accent) 14%, var(--surface-2));
  }
  .shop-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.9rem 0.95rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
  }
  .shop-name {
    flex: 1;
    font-weight: 500;
  }
  .shop-row.done .shop-name {
    text-decoration: line-through;
    color: var(--muted);
  }
  .anim-wrap {
    /* wrapper för crossfade/flip; deltar i .list-flexen som raden gjorde */
    display: block;
  }
  .checkbox {
    width: 22px;
    height: 22px;
    border-radius: 999px;
    border: 2px solid var(--border);
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: transparent;
    transition: background 0.15s, border-color 0.15s;
  }
  .checkbox .tick {
    stroke-dasharray: 24;
    stroke-dashoffset: 24;
  }
  .checkbox.on {
    background: var(--ok);
    border-color: var(--ok);
    color: #fff;
  }
  .checkbox.on .tick {
    stroke-dashoffset: 0;
  }
  /* Bocken ritas + rutan studsar */
  .checkbox.drawing {
    background: var(--ok);
    border-color: var(--ok);
    color: #fff;
    animation: box-pop 0.45s cubic-bezier(0.3, 1.6, 0.5, 1);
  }
  .checkbox.drawing .tick {
    animation: draw-tick 0.32s ease-out 0.08s forwards;
  }
  @keyframes draw-tick {
    to {
      stroke-dashoffset: 0;
    }
  }
  @keyframes box-pop {
    0% {
      transform: scale(0.8);
    }
    45% {
      transform: scale(1.25);
    }
    100% {
      transform: scale(1);
    }
  }
  /* Raden glöder svagt grönt medan bocken ritas */
  .shop-row.checking {
    background: color-mix(in srgb, var(--ok) 9%, var(--surface));
    border-color: color-mix(in srgb, var(--ok) 35%, var(--border));
  }
  .shop-row {
    transition: background 0.25s, border-color 0.25s;
  }
</style>
