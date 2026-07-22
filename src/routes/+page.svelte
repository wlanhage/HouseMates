<script lang="ts">
  import { onMount } from 'svelte';
  import { fly } from 'svelte/transition';
  import { flip } from 'svelte/animate';
  import { cubicOut } from 'svelte/easing';
  import { user, todosOpen, activity, events } from '$lib/client/stores';
  import { people, colorOf, initialOf, nameOf } from '$lib/client/people';
  import { refreshTodos, refreshActivity, refreshEvents, setTodoDone } from '$lib/client/data';
  import { todayStr, addDaysStr, dayHeading, relativeTime, dueLabel, hhmm } from '$lib/client/dates';
  import { eventSpan } from '$lib/client/agenda';
  import { groupActivity, describeGroup } from '$lib/client/activityFeed';
  import Avatar from '$lib/components/Avatar.svelte';
  import type { Activity, CalendarEvent, Todo } from '$lib/types';

  onMount(() => {
    void refreshTodos();
    void refreshActivity();
    void refreshEvents();
  });

  function greeting(): string {
    const h = new Date().getHours();
    if (h < 5) return 'God natt';
    if (h < 10) return 'God morgon';
    if (h < 18) return 'Hej';
    return 'God kväll';
  }
  const meName = $derived($user ? $user.name.replace(/\s*\(test\)/, '') : '');

  // ── Dagsbläddring (övre delen) ────────────────────────────
  const MIN_OFF = -7; // matchar eventfönstret bakåt
  const MAX_OFF = 42; // och framåt
  let dayOffset = $state(0);
  const today = todayStr();
  const day = $derived(addDaysStr(today, dayOffset));

  const dayEvents = $derived(
    $events
      .filter((e) => {
        const s = eventSpan(e);
        return day >= s.first && day <= s.last;
      })
      .sort((a, b) =>
        a.allDay !== b.allDay ? (a.allDay ? -1 : 1) : a.allDay ? 0 : a.start.localeCompare(b.start)
      )
  );

  // Uppgifter: deadline = dagen. På "Idag" även försenade.
  // Perioder (start_date..due_date) syns bara på sista dagen (= due_date).
  const dayTodos = $derived(
    $todosOpen
      .filter((t) => t.due_date && (t.due_date === day || (dayOffset === 0 && t.due_date < day)))
      .sort((a, b) => (a.due_date ?? '').localeCompare(b.due_date ?? ''))
  );

  // Swipe höger/vänster för att byta dag
  let dragX = $state(0);
  let swipeAxis = $state<'none' | 'h' | 'v'>('none');
  let sx = 0;
  let sy = 0;
  let swiping = false;

  function dayDown(e: PointerEvent) {
    sx = e.clientX;
    sy = e.clientY;
    swipeAxis = 'none';
    swiping = true;
  }
  function dayMove(e: PointerEvent) {
    if (!swiping) return;
    const dx = e.clientX - sx;
    const dy = e.clientY - sy;
    if (swipeAxis === 'none') {
      if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return;
      swipeAxis = Math.abs(dx) > Math.abs(dy) ? 'h' : 'v';
    }
    if (swipeAxis === 'h') dragX = dx;
  }
  function dayUp() {
    if (swipeAxis === 'h') {
      if (dragX < -55 && dayOffset < MAX_OFF) dayOffset++;
      else if (dragX > 55 && dayOffset > MIN_OFF) dayOffset--;
    }
    dragX = 0;
    swiping = false;
    swipeAxis = 'none';
  }

  // ── Delare (dra för att ändra fördelning; 50/50 vid varje mount) ──
  let ratio = $state(0.5);
  let splitEl: HTMLDivElement | undefined = $state();
  let dividerActive = $state(false);
  let dStartY = 0;
  let dStartRatio = 0.5;

  function divDown(e: PointerEvent) {
    dividerActive = true;
    dStartY = e.clientY;
    dStartRatio = ratio;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }
  function divMove(e: PointerEvent) {
    if (!dividerActive || !splitEl) return;
    const h = splitEl.clientHeight;
    ratio = Math.min(0.82, Math.max(0.18, dStartRatio + (e.clientY - dStartY) / h));
  }
  function divUp() {
    dividerActive = false;
  }

  // ── Historik (undre delen): endast inköp lagt till/avbockat ──
  const feed = $derived(
    $activity.filter((a) => a.type === 'shopping.added' || a.type === 'shopping.checked')
  );
  const groups = $derived(groupActivity(feed));

  type Group = ReturnType<typeof groupActivity>[number];
  let selectedGroup = $state<Group | null>(null);

  function entryLabel(a: Activity): string {
    const name = (a.payload?.name as string) ?? (a.payload?.title as string);
    if (name) return name;
    const count = a.payload?.count as number | undefined;
    return count != null ? `${count} avklarade` : '—';
  }

  function eventTime(e: CalendarEvent): string {
    return e.allDay ? 'Heldag' : hhmm(e.start);
  }

  // Avbockningsanimation: rita bocken, låt sedan raden flyga ut.
  let pendingDone = $state(new Set<string>());
  function handleDayDone(t: Todo) {
    if (pendingDone.has(t.id)) return;
    pendingDone = new Set(pendingDone).add(t.id);
    setTimeout(() => {
      pendingDone = new Set([...pendingDone].filter((id) => id !== t.id));
      void setTodoDone(t, true);
    }, 480);
  }
  function todoBadge(t: Todo): { text: string; kind: string } {
    const due = dueLabel(t.due_date!);
    if (dayOffset === 0) return due;
    return { text: t.start_date ? 'senast idag' : '', kind: due.kind };
  }
</script>

<svelte:head><title>Hem</title></svelte:head>

<div class="hero-mini">
  {greeting()}{meName ? `, ${meName}` : ''} 👋
</div>

<div class="split" data-no-ptr bind:this={splitEl}>
  <!-- Övre: dagen -->
  <section class="pane" style={`height:calc((100% - 22px) * ${ratio})`}>
    <header class="day-nav">
      <button class="day-chev" aria-label="Föregående dag" disabled={dayOffset <= MIN_OFF} onclick={() => dayOffset--}>
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 6-6 6 6 6" /></svg>
      </button>
      <div class="day-title">
        <strong>{dayHeading(day)}</strong>
        {#if dayOffset !== 0}
          <button class="today-link" onclick={() => (dayOffset = 0)}>Till idag</button>
        {/if}
      </div>
      <button class="day-chev" aria-label="Nästa dag" disabled={dayOffset >= MAX_OFF} onclick={() => dayOffset++}>
        <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
      </button>
    </header>

    <!-- svelte-ignore a11y_no_static_element_interactions -->
    <div
      class="day-body"
      style={`transform:translateX(${dragX * 0.35}px);opacity:${1 - Math.min(0.5, Math.abs(dragX) / 260)}`}
      onpointerdown={dayDown}
      onpointermove={dayMove}
      onpointerup={dayUp}
      onpointercancel={dayUp}
    >
      {#if dayEvents.length === 0 && dayTodos.length === 0}
        <div class="day-empty muted">Inget planerat {dayHeading(day).toLowerCase()}.</div>
      {:else}
        <div class="list" style="padding:0.15rem 2px 0.75rem">
          {#each dayEvents as e (e.id)}
            <div class="home-row">
              <span class="mini-dot" style={`background:${colorOf($people, e.createdBy)}`}></span>
              <span style="flex:1">{e.title}</span>
              <span class="muted" style="font-size:0.8rem;white-space:nowrap">{eventTime(e)}</span>
            </div>
          {/each}
          {#each dayTodos as t (t.id)}
            {@const badge = todoBadge(t)}
            <div
              class="home-row"
              class:checking={pendingDone.has(t.id)}
              out:fly={{ y: 36, duration: 320, easing: cubicOut }}
              animate:flip={{ duration: 280, easing: cubicOut }}
            >
              <button
                class="mini-check"
                class:drawing={pendingDone.has(t.id)}
                aria-label="Bocka av"
                onclick={() => handleDayDone(t)}
              >
                <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path class="tick" d="m5 12 5 5L20 7" /></svg>
              </button>
              <span style="flex:1">{t.title}</span>
              {#if badge.text}<span class="badge badge-{badge.kind}">{badge.text}</span>{/if}
              {#if t.assignee}
                <Avatar color={colorOf($people, t.assignee)} initial={initialOf($people, t.assignee)} size={20} />
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </section>

  <!-- Delare -->
  <button
    class="divider"
    class:grabbing={dividerActive}
    aria-label="Dra för att ändra fördelning"
    onpointerdown={divDown}
    onpointermove={divMove}
    onpointerup={divUp}
    onpointercancel={divUp}
  >
    <span class="divider-pill"></span>
  </button>

  <!-- Undre: inköpshistorik -->
  <section class="pane lower">
    <div class="section-title" style="margin:0 0 0.5rem">Nyligen i inköp</div>
    <div class="pane-scroll">
      {#if groups.length === 0}
        <div class="day-empty muted">Inget inköpshänt ännu.</div>
      {:else}
        <div class="list">
          {#each groups as g (g.key)}
            <button class="home-row group-btn" onclick={() => (selectedGroup = g)}>
              <Avatar color={colorOf($people, g.actor)} initial={initialOf($people, g.actor)} size={26} />
              <span style="flex:1;text-align:left">
                <strong>{nameOf($people, g.actor, $user?.id)}</strong>
                {describeGroup(g)}
              </span>
              <span class="muted" style="font-size:0.78rem;white-space:nowrap">{relativeTime(g.newest)}</span>
              <svg class="chev" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="m9 6 6 6-6 6" /></svg>
            </button>
          {/each}
        </div>
      {/if}
    </div>
  </section>
</div>

<svelte:window
  onkeydown={(e) => {
    if (selectedGroup && e.key === 'Escape') selectedGroup = null;
  }}
/>

{#if selectedGroup}
  <div class="scrim scrim-center">
    <button class="scrim-bg" aria-label="Stäng" onclick={() => (selectedGroup = null)}></button>
    <div class="popup" role="dialog" aria-modal="true" aria-label="Aktivitetsdetaljer">
      <header class="pop-head">
        <Avatar
          color={colorOf($people, selectedGroup.actor)}
          initial={initialOf($people, selectedGroup.actor)}
          size={30}
        />
        <div style="flex:1;min-width:0">
          <div class="pop-title">
            <strong>{nameOf($people, selectedGroup.actor, $user?.id)}</strong>
            {describeGroup(selectedGroup)}
          </div>
          <div class="muted" style="font-size:0.78rem">{relativeTime(selectedGroup.newest)}</div>
        </div>
        <button class="icon-btn" aria-label="Stäng" onclick={() => (selectedGroup = null)}>
          <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
        </button>
      </header>
      <ul class="pop-list">
        {#each selectedGroup.entries as e (e.id)}
          <li>
            <span class="dot" style={`background:${colorOf($people, e.actor)}`}></span>
            <span class="pop-item">{entryLabel(e)}</span>
            <span class="muted" style="font-size:0.75rem;white-space:nowrap">{relativeTime(e.created_at)}</span>
          </li>
        {/each}
      </ul>
    </div>
  </div>
{/if}

<style>
  .hero-mini {
    font-size: 1.05rem;
    font-weight: 750;
    margin: 0.15rem 0 0.6rem;
  }

  /* Split: fyller resten av skärmen (topbar + hero + nav borträknade) */
  .split {
    height: calc(
      100dvh - env(safe-area-inset-top, 0px) - 158px - var(--nav-h) - var(--safe-b)
    );
    min-height: 280px;
    display: flex;
    flex-direction: column;
  }
  .pane {
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
  .pane.lower {
    flex: 1;
  }
  .pane-scroll {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding-bottom: calc(var(--nav-h) + var(--safe-b) + 30px);
  }

  /* Dagsnavigering */
  .day-nav {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    margin-bottom: 0.45rem;
    flex: none;
  }
  .day-title {
    flex: 1;
    display: flex;
    align-items: baseline;
    justify-content: center;
    gap: 0.6rem;
    font-size: 1rem;
  }
  .day-title strong {
    font-weight: 800;
  }
  .today-link {
    border: none;
    background: none;
    color: var(--accent);
    font-weight: 700;
    font-size: 0.78rem;
    padding: 0;
  }
  .day-chev {
    width: 34px;
    height: 34px;
    border-radius: 999px;
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--muted);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
  }
  .day-chev:disabled {
    opacity: 0.35;
  }
  .day-body {
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    touch-action: pan-y;
  }
  .day-empty {
    text-align: center;
    padding: 1.6rem 1rem;
    font-size: 0.9rem;
  }

  /* Delare */
  .divider {
    flex: none;
    position: relative;
    height: 22px;
    border: none;
    background: none;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: grab;
    touch-action: none;
  }
  .divider::before {
    content: '';
    position: absolute;
    left: 0;
    right: 0;
    top: 50%;
    height: 1.5px;
    background: var(--muted);
    opacity: 0.28;
    border-radius: 1px;
  }
  .divider.grabbing {
    cursor: grabbing;
  }
  .divider-pill {
    position: relative;
    width: 56px;
    height: 5px;
    border-radius: 999px;
    background: var(--muted);
    opacity: 0.55;
    box-shadow: 0 0 0 6px var(--bg);
    transition: background 0.15s, width 0.15s, opacity 0.15s;
  }
  .divider:active .divider-pill,
  .divider.grabbing .divider-pill {
    opacity: 1;
  }
  .divider:active .divider-pill,
  .divider.grabbing .divider-pill {
    background: var(--accent);
    width: 72px;
  }

  .home-row {
    display: flex;
    align-items: center;
    gap: 0.65rem;
    padding: 0.85rem 0.95rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
  }
  .mini-check {
    width: 21px;
    height: 21px;
    border-radius: 7px;
    border: 2px solid var(--border);
    background: var(--surface);
    flex: none;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    color: transparent;
    padding: 0;
    transition: border-color 0.15s, background 0.15s;
  }
  .mini-check:active {
    border-color: var(--ok);
  }
  .mini-check .tick {
    stroke-dasharray: 24;
    stroke-dashoffset: 24;
  }
  .mini-check.drawing {
    background: var(--ok);
    border-color: var(--ok);
    color: #fff;
    animation: box-pop 0.45s cubic-bezier(0.3, 1.6, 0.5, 1);
  }
  .mini-check.drawing .tick {
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
  .home-row.checking {
    background: color-mix(in srgb, var(--ok) 9%, var(--surface));
    border-color: color-mix(in srgb, var(--ok) 35%, var(--border));
  }
  .mini-dot {
    width: 9px;
    height: 9px;
    border-radius: 999px;
    flex: none;
  }
  .group-btn {
    font: inherit;
    color: inherit;
    cursor: pointer;
    width: 100%;
    transition: transform 0.08s;
  }
  .group-btn:active {
    transform: scale(0.99);
  }
  .chev {
    color: var(--muted);
    flex: none;
    opacity: 0.7;
  }
  .pop-head {
    display: flex;
    align-items: center;
    gap: 0.7rem;
    padding: 0.9rem 0.9rem 0.9rem 1.05rem;
    border-bottom: 1px solid var(--border);
    flex: none;
  }
  .pop-title {
    font-size: 0.95rem;
    line-height: 1.3;
  }
  .pop-list {
    flex: 1;
    overflow-y: auto;
    margin: 0;
    padding: 0.35rem 0;
    list-style: none;
    overscroll-behavior: contain;
  }
  .pop-list li {
    display: flex;
    align-items: center;
    gap: 0.65rem;
    padding: 0.7rem 1.05rem;
  }
  .pop-list li + li {
    border-top: 1px solid color-mix(in srgb, var(--border) 55%, transparent);
  }
  .pop-item {
    flex: 1;
    min-width: 0;
    font-weight: 550;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
</style>
