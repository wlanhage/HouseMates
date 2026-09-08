<script lang="ts">
  import { onMount } from 'svelte';
  import { events, user, showToast } from '$lib/client/stores';
  import { people, colorOf, nameOf } from '$lib/client/people';
  import {
    refreshEvents,
    extendEvents,
    ensureEventsUntil,
    deleteEventAction,
    updateEventAction,
    type EventInput
  } from '$lib/client/data';
  import { buildAgenda, type AgendaEntry } from '$lib/client/agenda';
  import { ymd, todayStr, addDaysStr, dayHeading, hhmm } from '$lib/client/dates';
  import { buildMonth, addMonths, monthOf, WEEKDAYS } from '$lib/client/monthGrid';
  import EventForm from '$lib/components/EventForm.svelte';
  import { sheetDrag } from '$lib/client/sheetDrag';
  import type { CalendarEvent } from '$lib/types';

  // ── Vy: lista eller månadsrutnät, senaste valet sparas ──
  type View = 'list' | 'grid';
  const VIEW_KEY = 'kalender.view';
  function storedView(): View {
    try {
      return localStorage.getItem(VIEW_KEY) === 'grid' ? 'grid' : 'list';
    } catch {
      return 'list';
    }
  }
  let view = $state<View>(storedView());
  function setView(v: View) {
    view = v;
    try {
      localStorage.setItem(VIEW_KEY, v);
    } catch {
      /* privat läge – valet glöms */
    }
    if (v === 'grid') void ensureEventsUntil(months[months.length - 1].last);
  }

  const DAY = 86_400_000;
  const today = todayStr();
  const fromDay = ymd(new Date(Date.now() - 7 * DAY));
  let toDay = $state(ymd(new Date(Date.now() + 42 * DAY)));
  let selected = $state<CalendarEvent | null>(null);
  let editing = $state(false);
  let formKey = $state(0);
  let sentinel: HTMLDivElement | undefined = $state();
  let loadingMore = $state(false);

  // ── Lista ──
  const agenda = $derived(buildAgenda($events, fromDay, toDay));

  // ── Rutnät: innevarande månad + två framåt, fler vid skroll ──
  const start = monthOf(today);
  let monthCount = $state(3);
  const months = $derived(
    Array.from({ length: monthCount }, (_, i) => {
      const { year, month } = addMonths(start.year, start.month, i);
      return buildMonth(year, month);
    })
  );
  const gridAgenda = $derived(buildAgenda($events, months[0].first, months[months.length - 1].last));
  const byDay = $derived(new Map(gridAgenda.map((d) => [d.date, d.entries])));
  let dayOpen = $state<string | null>(null);
  const dayEntries = $derived(dayOpen ? (byDay.get(dayOpen) ?? []) : []);

  /** Upp till tre prickar i personernas färger för en dag. */
  function dotColors(date: string): string[] {
    const colors: string[] = [];
    for (const entry of byDay.get(date) ?? []) {
      const c = colorOf($people, entry.event.assignee);
      if (!colors.includes(c)) colors.push(c);
      if (colors.length === 3) break;
    }
    return colors;
  }

  async function loadMore() {
    if (loadingMore) return;
    loadingMore = true;
    if (view === 'list') {
      toDay = addDaysStr(toDay, 28);
      await extendEvents();
    } else {
      monthCount += 1;
      const { year, month } = addMonths(start.year, start.month, monthCount - 1);
      await ensureEventsUntil(buildMonth(year, month).last);
    }
    loadingMore = false;
  }

  onMount(() => {
    void refreshEvents();
    if (view === 'grid') void ensureEventsUntil(months[months.length - 1].last);
  });

  // Sentineln byts när vyn byts – koppla om observern varje gång.
  $effect(() => {
    const el = sentinel;
    if (!el) return;
    const io = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) void loadMore();
    });
    io.observe(el);
    return () => io.disconnect();
  });

  // ── Händelse: detalj/redigera/radera ──
  function openEvent(e: CalendarEvent) {
    dayOpen = null;
    selected = e;
  }

  function closeSheet() {
    selected = null;
    editing = false;
  }

  async function saveEdit(input: EventInput) {
    if (!selected) return;
    const res = await updateEventAction(selected.id, input);
    if (res.ok) {
      closeSheet();
    } else if (res.conflict) {
      selected = res.conflict;
      formKey++; // återöppna formuläret med den färska kopian (spec §9.4)
      showToast('Uppdaterades av någon annan – kontrollera och spara igen');
    }
  }

  async function removeEvent() {
    if (!selected) return;
    const ev = selected;
    closeSheet();
    await deleteEventAction(ev);
  }

  function timeLabel(e: CalendarEvent): string {
    return e.allDay ? 'Heldag' : `${hhmm(e.start)}–${hhmm(e.end)}`;
  }
</script>

<svelte:head><title>Kalender</title></svelte:head>

{#snippet eventRow(entry: AgendaEntry)}
  <button class="ev-row" onclick={() => openEvent(entry.event)}>
    <span class="ev-time">
      {#if entry.event.allDay}Heldag{:else}{hhmm(entry.event.start)}{/if}
    </span>
    <span class="ev-bar" style={`background:${colorOf($people, entry.event.assignee)}`}></span>
    <span class="ev-main">
      <span class="ev-title">
        {entry.event.title}
        {#if entry.event.isRecurring}<span class="recur" title="Återkommande">↻</span>{/if}
      </span>
      {#if entry.multiDay}
        <span class="ev-sub">dag {entry.dayIndex} av {entry.dayCount}</span>
      {:else if entry.event.location}
        <span class="ev-sub">{entry.event.location}</span>
      {/if}
    </span>
  </button>
{/snippet}

<div class="title-row">
  <h2 class="page-title">Kalender</h2>
  <div class="view-toggle" role="group" aria-label="Vy">
    <button class:on={view === 'list'} aria-label="Lista" aria-pressed={view === 'list'} onclick={() => setView('list')}>
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16" /></svg>
    </button>
    <button class:on={view === 'grid'} aria-label="Månad" aria-pressed={view === 'grid'} onclick={() => setView('grid')}>
      <svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4.5" width="18" height="16" rx="2.5" /><path d="M3 9.5h18M9 9.5v11M15 9.5v11M3 15h18" /></svg>
    </button>
  </div>
</div>

{#if view === 'list'}
  {#if agenda.length === 0}
    <div class="card empty">
      <span class="emoji">📅</span>
      Inga händelser. Koppla er delade iCloud-kalender under Inställningar.
    </div>
  {/if}

  {#each agenda as day (day.date)}
    <div class="day-head">{dayHeading(day.date)}</div>
    <div class="list" style="margin-bottom:1rem">
      {#each day.entries as entry (entry.event.id + day.date)}
        {@render eventRow(entry)}
      {/each}
    </div>
  {/each}

  <div bind:this={sentinel} style="height:1px"></div>
  {#if loadingMore}<div class="muted" style="text-align:center;padding:1rem">Laddar…</div>{/if}
{:else}
  {#each months as m (m.first)}
    <section class="month">
      <h3 class="month-head">{m.label}</h3>
      <div class="weekdays">
        {#each WEEKDAYS as w (w)}<span>{w}</span>{/each}
      </div>
      <div class="grid">
        {#each m.cells as c, i (m.first + i)}
          {#if c.date}
            {@const colors = dotColors(c.date)}
            <button
              class="cell"
              class:today={c.date === today}
              class:past={c.date < today}
              class:has={colors.length > 0}
              aria-label={`${dayHeading(c.date)}${colors.length ? ', händelser' : ''}`}
              onclick={() => (dayOpen = c.date)}
            >
              <span class="num">{c.day}</span>
              <span class="dots">
                {#each colors as col (col)}<i class="dot" style={`background:${col}`}></i>{/each}
              </span>
            </button>
          {:else}
            <span class="cell pad" aria-hidden="true"></span>
          {/if}
        {/each}
      </div>
    </section>
  {/each}

  <div bind:this={sentinel} style="height:1px"></div>
  {#if loadingMore}<div class="muted" style="text-align:center;padding:1rem">Laddar…</div>{/if}
{/if}

{#if dayOpen}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={() => (dayOpen = null)}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label={dayHeading(dayOpen)} use:sheetDrag={() => (dayOpen = null)}>
      <div class="sheet-handle"></div>
      <h3 style="padding:0 0.5rem 0.6rem">{dayHeading(dayOpen)}</h3>
      {#if dayEntries.length === 0}
        <p class="muted" style="padding:0 0.5rem 0.75rem;margin:0">Inget planerat den här dagen.</p>
      {:else}
        <div class="list" style="padding:0 0.5rem 0.5rem">
          {#each dayEntries as entry (entry.event.id)}
            {@render eventRow(entry)}
          {/each}
        </div>
      {/if}
    </div>
  </div>
{/if}

{#if selected}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={closeSheet}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Händelse" use:sheetDrag={closeSheet}>
      <div class="sheet-handle"></div>
      {#if editing}
        <h3 style="padding:0 0.5rem 0.5rem">Redigera händelse</h3>
        {#key formKey}
          <EventForm event={selected} submitLabel="Spara" onsubmit={saveEdit} />
        {/key}
      {:else}
        <div style="padding:0 0.5rem 0.5rem">
          <h3 style="margin-bottom:0.5rem">{selected.title}</h3>
          <div class="detail-row">🕒 {timeLabel(selected)}</div>
          {#if selected.location}<div class="detail-row">📍 {selected.location}</div>{/if}
          {#if selected.notes}<div class="detail-row">📝 {selected.notes}</div>{/if}
          {#if selected.isRecurring}<div class="detail-row">↻ Återkommande</div>{/if}
          <div class="detail-row">
            <span class="for-dot" style={`background:${colorOf($people, selected.assignee)}`}></span>
            {selected.assignee === 'both' ? 'Båda' : `För ${nameOf($people, selected.assignee, $user?.id)}`}
          </div>
          <div class="detail-row muted">
            {selected.createdBy ? `Skapad av ${nameOf($people, selected.createdBy)}` : 'Från Apple Kalender'}
          </div>
          <div class="row" style="gap:0.5rem;margin-top:1rem">
            {#if !selected.isRecurring}
              <button class="btn" style="flex:1" onclick={() => (editing = true)}>Redigera</button>
            {/if}
            <button class="btn btn-danger" style="flex:1" onclick={removeEvent}>Radera</button>
          </div>
          {#if selected.isRecurring}
            <p class="muted" style="font-size:0.8rem;margin:0.5rem 0 0">
              Enskilda förekomster kan inte redigeras i v1. Radera tar bort hela serien.
            </p>
          {/if}
        </div>
      {/if}
    </div>
  </div>
{/if}

<style>
  .title-row {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin: 0.35rem 0 1rem;
  }
  .title-row .page-title {
    margin: 0;
    flex: 1;
  }
  .view-toggle {
    display: flex;
    background: var(--surface-2);
    border-radius: 999px;
    padding: 3px;
  }
  .view-toggle button {
    width: 42px;
    height: 32px;
    border: none;
    border-radius: 999px;
    background: transparent;
    color: var(--muted);
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s, color 0.15s, box-shadow 0.15s;
  }
  .view-toggle button.on {
    background: var(--surface);
    color: var(--text);
    box-shadow: var(--shadow);
  }

  /* ── Lista ── */
  .day-head {
    font-size: 0.8rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
    margin: 0.75rem 0 0.4rem;
  }
  .ev-row {
    display: flex;
    align-items: stretch;
    gap: 0.65rem;
    width: 100%;
    text-align: left;
    padding: 0.75rem 0.85rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--surface);
    box-shadow: var(--shadow);
    color: var(--text);
    transition: transform 0.08s;
  }
  .ev-row:active {
    transform: scale(0.99);
  }
  .ev-time {
    flex: none;
    width: 48px;
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--muted);
    padding-top: 2px;
  }
  .ev-bar {
    flex: none;
    width: 4px;
    border-radius: 2px;
  }
  .ev-main {
    display: flex;
    flex-direction: column;
    min-width: 0;
  }
  .ev-title {
    font-weight: 600;
  }
  .recur {
    color: var(--muted);
    font-size: 0.85em;
  }
  .ev-sub {
    font-size: 0.8rem;
    color: var(--muted);
  }

  /* ── Rutnät ── */
  .month {
    margin-bottom: 1.4rem;
  }
  .month-head {
    font-size: 1.05rem;
    font-weight: 800;
    margin: 0.25rem 0 0.5rem;
  }
  .weekdays {
    display: grid;
    grid-template-columns: repeat(7, minmax(0, 1fr));
    text-align: center;
    font-size: 0.68rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--muted);
    margin-bottom: 0.3rem;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(7, minmax(0, 1fr));
    gap: 4px;
  }
  .cell {
    aspect-ratio: 1;
    min-width: 0;
    padding: 0;
    border: 1px solid var(--border);
    border-radius: 12px;
    background: var(--surface);
    color: var(--text);
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 3px;
    font-size: 0.85rem;
    font-weight: 600;
    transition: transform 0.08s;
  }
  .cell:active {
    transform: scale(0.94);
  }
  .cell.pad {
    visibility: hidden;
  }
  .cell.past {
    opacity: 0.45;
  }
  .cell.has {
    border-color: color-mix(in srgb, var(--accent) 40%, var(--border));
  }
  .cell .num {
    width: 26px;
    height: 26px;
    border-radius: 999px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }
  .cell.today .num {
    background: var(--accent);
    color: var(--on-accent);
    font-weight: 800;
  }
  .dots {
    display: flex;
    gap: 3px;
    height: 6px;
  }
  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }

  /* ── Detalj ── */
  .detail-row {
    padding: 0.3rem 0;
    font-size: 0.95rem;
  }
  .for-dot {
    display: inline-block;
    width: 10px;
    height: 10px;
    border-radius: 50%;
    margin-right: 0.45rem;
    vertical-align: middle;
  }
</style>
