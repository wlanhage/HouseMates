<script lang="ts">
  import { onMount } from 'svelte';
  import { crossfade, fly } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import { todosOpen, todosDone, chores, user, me } from '$lib/client/stores';
  import { people, colorOf, initialOf, nameOf } from '$lib/client/people';
  import { refreshTodos, refreshChores, setTodoDone, deleteTodo, tickChore, deleteChore, editChore } from '$lib/client/data';
  import { choreDueDate, intervalLabel, type ChoreInput } from '$lib/client/chores';
  import { sheetDrag } from '$lib/client/sheetDrag';
  import { dueLabel, fmtDate, daysAgoLabel } from '$lib/client/dates';
  import SwipeRow from '$lib/components/SwipeRow.svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import ChoreForm from '$lib/components/ChoreForm.svelte';
  import type { Todo, Chore } from '$lib/types';

  // Två flikar: "Att göra" (engångs – försvinner vid avbockning) och
  // "Städ" (återkommande – visar när det gjordes senast och av vem).
  let tab = $state<'todo' | 'chore'>('todo');
  let filter = $state<'alla' | 'du' | 'partner' | 'both'>('alla');
  let showDone = $state(false);

  // Avbockningsanimation: rita bocken, flyg sedan ner till "Klart".
  const [send, receive] = crossfade({
    duration: 420,
    easing: cubicOut,
    fallback: (node) => fly(node, { y: 40, duration: 300, easing: cubicOut })
  });
  let pending = $state(new Set<string>());
  const DRAW_MS = 480;

  function handleDone(t: Todo) {
    if (pending.has(t.id)) return;
    pending = new Set(pending).add(t.id);
    setTimeout(() => {
      pending = new Set([...pending].filter((id) => id !== t.id));
      void setTodoDone(t, true);
    }, DRAW_MS);
  }

  // Städ: bocken ritas, sedan uppdateras "senast" och raden sorteras om.
  let pendingChore = $state(new Set<string>());
  function handleChore(c: Chore) {
    if (pendingChore.has(c.id)) return;
    pendingChore = new Set(pendingChore).add(c.id);
    setTimeout(() => {
      pendingChore = new Set([...pendingChore].filter((id) => id !== c.id));
      void tickChore(c);
    }, DRAW_MS);
  }

  onMount(() => {
    void refreshTodos();
    void refreshChores();
  });

  const partnerId = $derived($me?.partner?.id ?? null);
  const meId = $derived($user?.id ?? null);

  function matchesFilter(assignee: string | null): boolean {
    if (filter === 'alla') return true;
    if (filter === 'du') return assignee === meId;
    if (filter === 'partner') return assignee === partnerId;
    return assignee === 'both';
  }
  const filtered = $derived($todosOpen.filter((t) => matchesFilter(t.assignee)));
  const filteredChores = $derived($chores.filter((c) => matchesFilter(c.assignee)));

  function lastDoneText(c: Chore): string {
    if (!c.last_done_at) return 'Aldrig gjord';
    return `✓ ${nameOf($people, c.last_done_by, meId ?? undefined)}, ${daysAgoLabel(c.last_done_at)}`;
  }

  // Håll inne på en syssla för att redigera den.
  let editingChore = $state<Chore | null>(null);

  async function saveChore(input: ChoreInput) {
    if (!editingChore) return;
    await editChore(editingChore, input);
    editingChore = null;
  }

  function removeEditingChore() {
    if (!editingChore) return;
    const c = editingChore;
    editingChore = null;
    void deleteChore(c);
  }
</script>

<svelte:head><title>Att göra</title></svelte:head>

<h2 class="page-title">Att göra</h2>

<div class="tabs" role="tablist">
  <button role="tab" aria-selected={tab === 'todo'} class:on={tab === 'todo'} onclick={() => (tab = 'todo')}>Att göra</button>
  <button role="tab" aria-selected={tab === 'chore'} class:on={tab === 'chore'} onclick={() => (tab = 'chore')}>Städ</button>
</div>

<div class="pills">
  <button class="pill" class:on={filter === 'alla'} onclick={() => (filter = 'alla')}>Alla</button>
  <button class="pill" class:on={filter === 'du'} onclick={() => (filter = 'du')}>Du</button>
  {#if $me?.partner}
    <button class="pill" class:on={filter === 'partner'} onclick={() => (filter = 'partner')}>
      {nameOf($people, partnerId)}
    </button>
  {/if}
  <button class="pill" class:on={filter === 'both'} onclick={() => (filter = 'both')}>Båda</button>
</div>

{#if tab === 'todo'}
  {#if filtered.length === 0}
    <div class="card empty">
      <span class="emoji">✅</span>
      Inga öppna uppgifter här.
    </div>
  {:else}
    <div class="list">
      {#each filtered as t (t.id)}
        {@const due = t.due_date ? dueLabel(t.due_date) : null}
        <div
          class="anim-wrap"
          in:receive={{ key: t.id }}
          out:send={{ key: t.id }}
          animate:flip={{ duration: 300, easing: cubicOut }}
        >
          <SwipeRow ontap={() => handleDone(t)} ondelete={() => void deleteTodo(t)}>
            <div class="todo-row" class:checking={pending.has(t.id)}>
              <span class="checkbox" data-tap class:drawing={pending.has(t.id)}>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
              </span>
              <div class="todo-main">
                <div class="todo-title">{t.title}</div>
                {#if t.notes}<div class="todo-notes">{t.notes}</div>{/if}
              </div>
              {#if due}
                <span class="badge badge-{due.kind}">
                  {#if t.start_date}{fmtDate(t.start_date)} – {due.text === 'Idag' || due.text === 'Imorgon' ? due.text.toLowerCase() : fmtDate(t.due_date!)}{:else}{due.text}{/if}
                </span>
              {/if}
              {#if t.assignee}
                <Avatar color={colorOf($people, t.assignee)} initial={initialOf($people, t.assignee)} size={22} />
              {/if}
            </div>
          </SwipeRow>
        </div>
      {/each}
    </div>
  {/if}

  {#if $todosDone.length}
    <button class="done-header" onclick={() => (showDone = !showDone)}>
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style={`transform:rotate(${showDone ? 90 : 0}deg);transition:transform .15s`}>
        <path d="m9 6 6 6-6 6" />
      </svg>
      Klart · {$todosDone.length}
    </button>
    {#if showDone}
      <div class="list">
        {#each $todosDone as t (t.id)}
          <div
            class="anim-wrap"
            in:receive={{ key: t.id }}
            out:send={{ key: t.id }}
            animate:flip={{ duration: 300, easing: cubicOut }}
          >
            <SwipeRow ontap={() => void setTodoDone(t, false)} ondelete={() => void deleteTodo(t)}>
              <div class="todo-row done">
                <span class="checkbox on" data-tap>
                  <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
                </span>
                <div class="todo-main"><div class="todo-title">{t.title}</div></div>
                {#if t.done_by}
                  <Avatar color={colorOf($people, t.done_by)} initial={initialOf($people, t.done_by)} size={22} />
                {/if}
              </div>
            </SwipeRow>
          </div>
        {/each}
      </div>
    {/if}
  {/if}
{:else}
  {#if filteredChores.length === 0}
    <div class="card empty">
      <span class="emoji">🧽</span>
      Inga städsysslor här än. Lägg till med plus-knappen → Ny städsyssla.
    </div>
  {:else}
    <div class="list">
      {#each filteredChores as c (c.id)}
        {@const due = choreDueDate(c)}
        {@const dueBadge = due ? dueLabel(due) : null}
        <div class="anim-wrap" animate:flip={{ duration: 320, easing: cubicOut }}>
          <SwipeRow
            ontap={() => handleChore(c)}
            ondelete={() => void deleteChore(c)}
            onbodytap={() => (editingChore = c)}
            onlongpress={() => (editingChore = c)}
          >
            <div
              class="todo-row chore"
              class:checking={pendingChore.has(c.id)}
              style={c.assignee ? `--who:${colorOf($people, c.assignee)}` : ''}
            >
              <span class="checkbox" data-tap class:drawing={pendingChore.has(c.id)}>
                <svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
              </span>
              <div class="todo-main">
                <div class="chore-top">
                  <span class="todo-title">{c.title}</span>
                  {#if dueBadge}<span class="badge badge-{dueBadge.kind}">{dueBadge.text}</span>{/if}
                </div>
                <div class="chore-meta">
                  {#if c.interval_days}<span>↻ {intervalLabel(c.interval_days)}</span>{/if}
                  <span class:never={!c.last_done_at}>{lastDoneText(c)}</span>
                </div>
              </div>
            </div>
          </SwipeRow>
        </div>
      {/each}
    </div>
    <p class="muted hint">Tryck på bocken när sysslan är gjord. Tryck på namnet för att redigera.</p>
  {/if}
{/if}

{#if editingChore}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={() => (editingChore = null)}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Redigera städsyssla" use:sheetDrag={() => (editingChore = null)}>
      <div class="sheet-handle"></div>
      <h3 style="padding:0 0.5rem 0.5rem">Redigera städsyssla</h3>
      <ChoreForm chore={editingChore} submitLabel="Spara" onsubmit={saveChore} />
      <button class="danger-link" onclick={removeEditingChore}>Ta bort städsyssla</button>
    </div>
  </div>
{/if}

<style>
  .tabs {
    display: flex;
    background: var(--surface-2);
    border-radius: 999px;
    padding: 3px;
    margin-bottom: 0.9rem;
  }
  .tabs button {
    flex: 1;
    border: none;
    background: transparent;
    border-radius: 999px;
    padding: 0.55rem;
    font-size: 0.9rem;
    font-weight: 700;
    color: var(--muted);
    transition: background 0.15s, color 0.15s, box-shadow 0.15s;
  }
  .tabs button.on {
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow);
  }
  .pills {
    display: flex;
    gap: 0.4rem;
    overflow-x: auto;
    margin-bottom: 1rem;
    scrollbar-width: none;
  }
  .pills::-webkit-scrollbar {
    display: none;
  }
  .pill {
    flex: none;
    border: 1px solid var(--border);
    background: var(--surface);
    border-radius: 999px;
    padding: 0.42rem 0.9rem;
    font-size: 0.85rem;
    font-weight: 650;
    color: var(--muted);
    box-shadow: var(--shadow);
    transition: background 0.15s, color 0.15s;
  }
  .pill.on {
    background: var(--accent);
    color: var(--on-accent);
    border-color: var(--accent);
  }
  .todo-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.9rem 0.95rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
    transition: background 0.25s, border-color 0.25s;
  }
  .todo-row.chore {
    box-shadow: inset 4px 0 0 var(--who, transparent), var(--shadow);
  }
  .chore-top {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
  }
  .chore-top .todo-title {
    flex: 1;
    min-width: 0;
  }
  .chore-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.1rem 0.75rem;
    margin-top: 0.2rem;
    font-size: 0.78rem;
    color: var(--muted);
  }
  .chore-meta span {
    white-space: nowrap;
  }
  .chore-meta .never {
    font-style: italic;
  }
  .todo-main {
    flex: 1;
    min-width: 0;
  }
  .todo-title {
    font-weight: 500;
  }
  .todo-row.done .todo-title {
    text-decoration: line-through;
    color: var(--muted);
  }
  .todo-notes {
    font-size: 0.8rem;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .todo-notes.wrap {
    white-space: normal;
  }
  .todo-notes.never {
    font-style: italic;
  }
  .danger-link {
    display: block;
    margin: 1rem auto 0.25rem;
    border: none;
    background: none;
    color: var(--danger);
    font-weight: 600;
    font-size: 0.9rem;
  }
  .hint {
    font-size: 0.78rem;
    text-align: center;
    margin-top: 1rem;
  }
  .anim-wrap {
    display: block;
  }
  .checkbox {
    width: 22px;
    height: 22px;
    border-radius: 6px;
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
  .todo-row.checking {
    background: color-mix(in srgb, var(--ok) 9%, var(--surface));
    border-color: color-mix(in srgb, var(--ok) 35%, var(--border));
  }
  .done-header {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    width: 100%;
    border: none;
    background: none;
    color: var(--muted);
    font-weight: 700;
    font-size: 0.8rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    margin: 1.5rem 0 0.5rem;
    padding: 0;
  }
</style>
