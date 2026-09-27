<script lang="ts">
  import { onMount, untrack } from 'svelte';
  import { dayHeading } from '$lib/client/dates';
  import {
    choreDueDate,
    intervalDays,
    intervalLabel,
    splitInterval,
    type ChoreInput,
    type IntervalUnit
  } from '$lib/client/chores';
  import type { Chore } from '$lib/types';
  import AssigneePicker from './AssigneePicker.svelte';

  let {
    chore = null,
    submitLabel = 'Lägg till',
    onsubmit
  }: {
    chore?: Chore | null;
    submitLabel?: string;
    onsubmit: (input: ChoreInput) => Promise<void>;
  } = $props();

  const init = untrack(() => chore);
  const initialInterval = splitInterval(init?.interval_days ?? null);

  let title = $state(init?.title ?? '');
  let assignee = $state<string | null>(init ? init.assignee : 'both');
  let count = $state(initialInterval.count);
  let unit = $state<IntervalUnit>(initialInterval.unit);
  let busy = $state(false);
  let titleField: HTMLInputElement | undefined = $state();

  const interval = $derived(intervalDays(count, unit));
  const due = $derived(
    choreDueDate({
      interval_days: interval,
      last_done_at: init?.last_done_at ?? null,
      created_at: init?.created_at ?? new Date().toISOString()
    })
  );

  onMount(() => {
    if (!init) setTimeout(() => titleField?.focus(), 30);
  });

  async function submit(e: Event) {
    e.preventDefault();
    if (!title.trim()) return;
    busy = true;
    try {
      await onsubmit({ title, assignee, interval_days: interval });
    } finally {
      busy = false;
    }
  }
</script>

<form onsubmit={submit} style="padding:0 0.5rem">
  <div class="field">
    <label for="ch-title">Syssla</label>
    <input id="ch-title" bind:this={titleField} class="input" bind:value={title} placeholder="t.ex. Byta sängkläder" autocomplete="off" />
  </div>
  <div class="field">
    <span class="label-txt">Vem gör det?</span>
    <AssigneePicker bind:value={assignee} allowNone />
  </div>
  <div class="field">
    <label for="ch-count">Hur ofta? <span class="opt">valfritt</span></label>
    <div class="interval">
      <span class="muted">Var</span>
      <input id="ch-count" class="input count" type="number" inputmode="numeric" min="1" bind:value={count} placeholder="3" />
      <select class="input unit" bind:value={unit} aria-label="Enhet">
        <option value="veckor">veckor</option>
        <option value="dagar">dagar</option>
      </select>
    </div>
  </div>
  <p class="muted hint">
    {#if interval && due}
      <strong>{intervalLabel(interval)}</strong> · sista dag {dayHeading(due).toLowerCase()}. Syns i kalendern och räknas om när den bockas av.
    {:else}
      Utan intervall visar listan bara när det gjordes senast och av vem.
    {/if}
  </p>
  <button class="btn btn-primary btn-block" type="submit" disabled={busy || !title.trim()}>
    {busy ? 'Sparar…' : submitLabel}
  </button>
</form>

<style>
  .opt {
    font-weight: 500;
    color: var(--muted);
    opacity: 0.8;
  }
  .interval {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }
  .interval .count {
    width: 5rem;
    flex: none;
  }
  .interval .unit {
    flex: 1;
    min-width: 0;
  }
  .hint {
    font-size: 0.78rem;
    margin: -0.4rem 0 0.8rem;
    line-height: 1.45;
  }
  .hint strong {
    color: var(--accent);
  }
</style>
