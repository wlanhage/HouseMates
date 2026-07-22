<script lang="ts">
  import { onMount } from 'svelte';
  import { crossfade, fly } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import { todosOpen, todosDone, user, me } from '$lib/client/stores';
  import { people, colorOf, initialOf, nameOf } from '$lib/client/people';
  import { refreshTodos, setTodoDone, deleteTodo } from '$lib/client/data';
  import { dueLabel, fmtDate } from '$lib/client/dates';
  import SwipeRow from '$lib/components/SwipeRow.svelte';
  import Avatar from '$lib/components/Avatar.svelte';
  import type { Todo } from '$lib/types';

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

  onMount(() => {
    void refreshTodos();
  });

  const partnerId = $derived($me?.partner?.id ?? null);
  const meId = $derived($user?.id ?? null);

  const filtered = $derived(
    $todosOpen.filter((t) => {
      if (filter === 'alla') return true;
      if (filter === 'du') return t.assignee === meId;
      if (filter === 'partner') return t.assignee === partnerId;
      if (filter === 'both') return t.assignee === 'both';
      return true;
    })
  );

  function assigneeColor(t: Todo): string {
    return colorOf($people, t.assignee);
  }
</script>

<svelte:head><title>Att göra</title></svelte:head>

<h2 class="page-title">Att göra</h2>

<div class="pills">
  <button class="pill" class:on={filter === 'alla'} onclick={() => (filter = 'alla')}>Alla</button>
  <button class="pill" class:on={filter === 'du'} onclick={() => (filter = 'du')}>Du</button>
  {#if $me?.partner}
    <button class="pill" class:on={filter === 'partner'} onclick={() => (filter = 'partner')}>
      {nameOf($people, partnerId)}
    </button>
  {/if}
  <button class="pill" class:on={filter === 'both'} onclick={() => (filter = 'both')}>Gemensamt</button>
</div>

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
            <span class="checkbox" class:drawing={pending.has(t.id)}>
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
              <Avatar color={assigneeColor(t)} initial={initialOf($people, t.assignee)} size={22} />
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
              <span class="checkbox on">
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

<style>
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
  .todo-row {
    transition: background 0.25s, border-color 0.25s;
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
