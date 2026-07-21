<script lang="ts">
  import { onMount } from 'svelte';
  import { events, showToast } from '$lib/client/stores';
  import { people, colorOf, nameOf } from '$lib/client/people';
  import {
    refreshEvents,
    extendEvents,
    deleteEventAction,
    updateEventAction,
    type EventInput
  } from '$lib/client/data';
  import { buildAgenda } from '$lib/client/agenda';
  import { ymd, addDaysStr, dayHeading, hhmm } from '$lib/client/dates';
  import EventForm from '$lib/components/EventForm.svelte';
  import type { CalendarEvent } from '$lib/types';

  const DAY = 86_400_000;
  const fromDay = ymd(new Date(Date.now() - 7 * DAY));
  let toDay = $state(ymd(new Date(Date.now() + 42 * DAY)));
  let selected = $state<CalendarEvent | null>(null);
  let editing = $state(false);
  let formKey = $state(0);
  let sentinel: HTMLDivElement | undefined = $state();
  let loadingMore = $state(false);

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

  const agenda = $derived(buildAgenda($events, fromDay, toDay));

  onMount(() => {
    void refreshEvents();
    if (!sentinel) return;
    const io = new IntersectionObserver(async (entries) => {
      if (entries[0].isIntersecting && !loadingMore) {
        loadingMore = true;
        toDay = addDaysStr(toDay, 28);
        await extendEvents();
        loadingMore = false;
      }
    });
    io.observe(sentinel);
    return () => io.disconnect();
  });

  function timeLabel(e: CalendarEvent): string {
    return e.allDay ? 'Heldag' : `${hhmm(e.start)}–${hhmm(e.end)}`;
  }
</script>

<svelte:head><title>Kalender</title></svelte:head>

<h2 class="page-title">Kalender</h2>

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
      <button class="ev-row" onclick={() => (selected = entry.event)}>
        <span class="ev-time">
          {#if entry.event.allDay}Heldag{:else}{hhmm(entry.event.start)}{/if}
        </span>
        <span class="ev-bar" style={`background:${colorOf($people, entry.event.createdBy)}`}></span>
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
    {/each}
  </div>
{/each}

<div bind:this={sentinel} style="height:1px"></div>
{#if loadingMore}<div class="muted" style="text-align:center;padding:1rem">Laddar…</div>{/if}

{#if selected}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={closeSheet}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Händelse">
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
  .detail-row {
    padding: 0.3rem 0;
    font-size: 0.95rem;
  }
</style>
