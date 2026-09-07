<script lang="ts">
  import { untrack } from 'svelte';
  import { todayStr, dayHeading } from '$lib/client/dates';
  import { eventInputFrom, fieldsFrom, emptyFields } from '$lib/client/eventForm';
  import type { CalendarEvent } from '$lib/types';
  import type { EventInput } from '$lib/client/data';
  import AssigneePicker from './AssigneePicker.svelte';

  let {
    event = null,
    submitLabel = 'Spara',
    onsubmit
  }: {
    event?: CalendarEvent | null;
    submitLabel?: string;
    onsubmit: (input: EventInput) => Promise<void>;
  } = $props();

  // Läs prop:en en gång (komponenten remountas via {#key} vid konflikt).
  const init = untrack(() => event);
  let f = $state(init ? fieldsFrom(init) : emptyFields(todayStr()));
  let busy = $state(false);
  let error = $state('');

  const timed = $derived(!!f.startTime);

  // Förhandsvisning av vad som sparas: "ons 16 sep · 10:00–11:00"
  const preview = $derived.by(() => {
    const r = eventInputFrom({ ...f, title: f.title || 'x' });
    if (!r.ok) return '';
    const days = f.endDate && f.endDate !== f.date ? `${dayHeading(f.date)} till ${dayHeading(f.endDate)}` : dayHeading(f.date);
    if (r.input.allDay) return `${days} · hela dagen`;
    const end = new Date(r.input.end);
    const hh = `${String(end.getHours()).padStart(2, '0')}:${String(end.getMinutes()).padStart(2, '0')}`;
    return `${days} · ${f.startTime}–${hh}`;
  });

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    const r = eventInputFrom(f);
    if (!r.ok) {
      error = r.error;
      return;
    }
    busy = true;
    try {
      await onsubmit(r.input);
    } finally {
      busy = false;
    }
  }
</script>

<form onsubmit={submit} style="padding:0 0.5rem">
  <div class="field">
    <label for="ev-title">Vad?</label>
    <input id="ev-title" class="input" bind:value={f.title} placeholder="t.ex. Gym, Middag hos mamma, Bortrest" autocomplete="off" />
  </div>

  <div class="field">
    <span class="label-txt">För vem?</span>
    <AssigneePicker bind:value={f.assignee} />
  </div>

  <div class="row" style="gap:0.5rem">
    <div class="field" style="flex:1">
      <label for="ev-date">Datum</label>
      <input id="ev-date" class="input" type="date" bind:value={f.date} />
    </div>
    <div class="field" style="flex:1">
      <label for="ev-end-date">Till <span class="opt">valfritt</span></label>
      <div class="clearable">
        <input id="ev-end-date" class="input" type="date" min={f.date} bind:value={f.endDate} />
        {#if f.endDate}
          <button type="button" class="clear" aria-label="Rensa slutdatum" onclick={() => (f.endDate = '')}>×</button>
        {/if}
      </div>
    </div>
  </div>

  <div class="row" style="gap:0.5rem">
    <div class="field" style="flex:1">
      <label for="ev-start">Tid <span class="opt">valfritt</span></label>
      <div class="clearable">
        <input id="ev-start" class="input" type="time" bind:value={f.startTime} />
        {#if f.startTime}
          <button type="button" class="clear" aria-label="Rensa tid" onclick={() => { f.startTime = ''; f.endTime = ''; }}>×</button>
        {/if}
      </div>
    </div>
    <div class="field" style="flex:1">
      <label for="ev-end">Slut <span class="opt">valfritt</span></label>
      <div class="clearable">
        <input id="ev-end" class="input" type="time" bind:value={f.endTime} disabled={!timed} />
        {#if f.endTime}
          <button type="button" class="clear" aria-label="Rensa sluttid" onclick={() => (f.endTime = '')}>×</button>
        {/if}
      </div>
    </div>
  </div>

  <p class="summary">
    {#if preview}<strong>{preview}</strong><br />{/if}
    <span class="muted">
      {#if !timed}Utan tid markeras bara dagen, som "Gym" eller "Bortrest".{:else if !f.endTime}Utan sluttid blir det en timme.{:else}&nbsp;{/if}
    </span>
  </p>

  <div class="field">
    <label for="ev-loc">Plats <span class="opt">valfritt</span></label>
    <input id="ev-loc" class="input" bind:value={f.location} placeholder="t.ex. Hemma" autocomplete="off" />
  </div>
  <div class="field">
    <label for="ev-notes">Anteckningar <span class="opt">valfritt</span></label>
    <input id="ev-notes" class="input" bind:value={f.notes} placeholder="Detaljer…" autocomplete="off" />
  </div>

  {#if error}<p class="error-text">{error}</p>{/if}
  <button class="btn btn-primary btn-block" type="submit" disabled={busy}>
    {busy ? 'Sparar…' : submitLabel}
  </button>
</form>

<style>
  /* Datum-/tidfält har inbyggd minsta bredd – låt dem krympa i tvåkolumnsraderna */
  .row > .field {
    min-width: 0;
  }
  .row .input {
    min-width: 0;
    width: 100%;
  }
  .opt {
    font-weight: 500;
    color: var(--muted);
    opacity: 0.8;
  }
  .clearable {
    position: relative;
  }
  .clearable .input {
    padding-right: 2.2rem;
  }
  .clear {
    position: absolute;
    right: 0.35rem;
    top: 50%;
    transform: translateY(-50%);
    width: 28px;
    height: 28px;
    border-radius: 999px;
    border: none;
    background: var(--surface-2);
    color: var(--muted);
    font-size: 1.1rem;
    line-height: 1;
  }
  .summary {
    margin: -0.2rem 0 0.9rem;
    font-size: 0.85rem;
    line-height: 1.45;
    min-height: 2.5rem;
  }
  .summary strong {
    color: var(--accent);
  }
  input[type='time']:disabled,
  input[type='date']:disabled {
    opacity: 0.45;
  }
</style>
