<script lang="ts">
  import { untrack } from 'svelte';
  import { addDaysStr, todayStr } from '$lib/client/dates';
  import type { CalendarEvent } from '$lib/types';
  import type { EventInput } from '$lib/client/data';

  let {
    event = null,
    submitLabel = 'Spara',
    onsubmit
  }: {
    event?: CalendarEvent | null;
    submitLabel?: string;
    onsubmit: (input: EventInput) => Promise<void>;
  } = $props();

  function pad(n: number) {
    return String(n).padStart(2, '0');
  }
  function toLocalInput(iso: string): string {
    const d = new Date(iso);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
  function defaultTimed(offsetH: number): string {
    const d = new Date();
    d.setMinutes(0, 0, 0);
    d.setHours(d.getHours() + offsetH);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  // Läs prop:en en gång (komponenten remountas via {#key} vid konflikt).
  const init = untrack(() => event);

  let title = $state(init?.title ?? '');
  let allDay = $state(init?.allDay ?? false);
  let location = $state(init?.location ?? '');
  let notes = $state(init?.notes ?? '');

  // Heldag: rena datum (slut visas inklusivt i UI, lagras exklusivt).
  let startDate = $state(init?.allDay ? init.start : todayStr());
  let endDate = $state(init?.allDay ? addDaysStr(init.end, -1) : todayStr());
  // Tidsatt: datetime-local (lokal tid).
  let startDT = $state(init && !init.allDay ? toLocalInput(init.start) : defaultTimed(1));
  let endDT = $state(init && !init.allDay ? toLocalInput(init.end) : defaultTimed(2));

  let busy = $state(false);
  let error = $state('');

  async function submit(e: Event) {
    e.preventDefault();
    error = '';
    if (!title.trim()) {
      error = 'Ange en titel.';
      return;
    }
    let input: EventInput;
    if (allDay) {
      if (endDate < startDate) {
        error = 'Slutdatum måste vara samma eller efter start.';
        return;
      }
      input = {
        title: title.trim(),
        allDay: true,
        start: startDate,
        end: addDaysStr(endDate, 1), // exklusivt
        location: location.trim() || null,
        notes: notes.trim() || null
      };
    } else {
      const startIso = new Date(startDT).toISOString();
      const endIso = new Date(endDT).toISOString();
      if (new Date(endIso) <= new Date(startIso)) {
        error = 'Sluttid måste vara efter starttid.';
        return;
      }
      input = {
        title: title.trim(),
        allDay: false,
        start: startIso,
        end: endIso,
        location: location.trim() || null,
        notes: notes.trim() || null
      };
    }
    busy = true;
    try {
      await onsubmit(input);
    } finally {
      busy = false;
    }
  }
</script>

<form onsubmit={submit} style="padding:0 0.5rem">
  <div class="field">
    <label for="ev-title">Titel</label>
    <input id="ev-title" class="input" bind:value={title} placeholder="Vad händer?" autocomplete="off" />
  </div>

  <label class="toggle-row">
    <span>Heldag</span>
    <input type="checkbox" bind:checked={allDay} />
  </label>

  {#if allDay}
    <div class="field">
      <label for="ev-sd">Från</label>
      <input id="ev-sd" class="input" type="date" bind:value={startDate} />
    </div>
    <div class="field">
      <label for="ev-ed">Till (inklusive)</label>
      <input id="ev-ed" class="input" type="date" bind:value={endDate} />
    </div>
  {:else}
    <div class="field">
      <label for="ev-sdt">Start</label>
      <input id="ev-sdt" class="input" type="datetime-local" bind:value={startDT} />
    </div>
    <div class="field">
      <label for="ev-edt">Slut</label>
      <input id="ev-edt" class="input" type="datetime-local" bind:value={endDT} />
    </div>
  {/if}

  <div class="field">
    <label for="ev-loc">Plats (valfritt)</label>
    <input id="ev-loc" class="input" bind:value={location} placeholder="t.ex. Hemma" autocomplete="off" />
  </div>
  <div class="field">
    <label for="ev-notes">Anteckningar (valfritt)</label>
    <input id="ev-notes" class="input" bind:value={notes} placeholder="Detaljer…" autocomplete="off" />
  </div>

  {#if error}<p class="error-text">{error}</p>{/if}
  <button class="btn btn-primary btn-block" type="submit" disabled={busy}>
    {busy ? 'Sparar…' : submitLabel}
  </button>
</form>

<style>
  .toggle-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.6rem 0.1rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
  }
  .toggle-row input {
    width: 20px;
    height: 20px;
  }
</style>
