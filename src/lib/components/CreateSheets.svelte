<script lang="ts">
  import { createKind, user, me } from '$lib/client/stores';
  import { people, nameOf } from '$lib/client/people';
  import { createShopping, createTodo, createEventAction, type EventInput } from '$lib/client/data';
  import EventForm from './EventForm.svelte';

  // Inköp
  let shopName = $state('');
  let shopQty = $state('');
  // Todo
  let todoTitle = $state('');
  let todoNotes = $state('');
  let todoAssignee = $state<string | null>(null);
  let todoStart = $state('');
  let todoDue = $state('');
  let todoError = $state('');

  let firstField: HTMLInputElement | undefined = $state();

  const meId = $derived($user?.id ?? null);
  const partnerId = $derived($me?.partner?.id ?? null);

  function close() {
    createKind.set(null);
  }

  // Fokusera första fältet + nollställ när sheeten öppnas.
  $effect(() => {
    const kind = $createKind;
    if (kind === 'shopping') {
      shopName = '';
      shopQty = '';
    } else if (kind === 'todo') {
      todoTitle = '';
      todoNotes = '';
      todoAssignee = null;
      todoStart = '';
      todoDue = '';
      todoError = '';
    }
    if (kind) setTimeout(() => firstField?.focus(), 30);
  });

  async function submitShopping(e: Event) {
    e.preventDefault();
    if (!shopName.trim()) return;
    await createShopping(shopName, shopQty);
    close();
  }

  async function submitTodo(e: Event) {
    e.preventDefault();
    todoError = '';
    if (!todoTitle.trim()) return;
    if (todoStart && !todoDue) {
      todoError = 'En period kräver en deadline.';
      return;
    }
    if (todoStart && todoDue && todoStart > todoDue) {
      todoError = 'Startdatum måste vara före deadline.';
      return;
    }
    await createTodo({
      title: todoTitle,
      notes: todoNotes,
      assignee: todoAssignee,
      start_date: todoStart || null,
      due_date: todoDue || null
    });
    close();
  }

  async function submitEvent(input: EventInput) {
    const success = await createEventAction(input);
    if (success) close();
  }
</script>

<svelte:window
  onkeydown={(e) => {
    if ($createKind && e.key === 'Escape') close();
  }}
/>

{#if $createKind}
  <div class="scrim">
    <button class="scrim-bg" aria-label="Stäng" onclick={close}></button>
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Skapa nytt">
      <div class="sheet-handle"></div>

      {#if $createKind === 'shopping'}
        <h3 style="padding:0 0.5rem 0.5rem">Ny vara</h3>
        <form onsubmit={submitShopping} style="padding:0 0.5rem">
          <div class="field">
            <label for="c-name">Vara</label>
            <input id="c-name" bind:this={firstField} class="input" bind:value={shopName} placeholder="t.ex. Mjölk" autocomplete="off" />
          </div>
          <div class="field">
            <label for="c-qty">Antal (valfritt)</label>
            <input id="c-qty" class="input" bind:value={shopQty} placeholder="t.ex. 2 l" autocomplete="off" />
          </div>
          <button class="btn btn-primary btn-block" type="submit" disabled={!shopName.trim()}>Lägg till</button>
        </form>
      {:else if $createKind === 'todo'}
        <h3 style="padding:0 0.5rem 0.5rem">Ny uppgift</h3>
        <form onsubmit={submitTodo} style="padding:0 0.5rem">
          <div class="field">
            <label for="t-title">Titel</label>
            <input id="t-title" bind:this={firstField} class="input" bind:value={todoTitle} placeholder="Vad ska göras?" autocomplete="off" />
          </div>
          <div class="field">
            <label for="t-notes">Anteckningar (valfritt)</label>
            <input id="t-notes" class="input" bind:value={todoNotes} placeholder="Detaljer…" autocomplete="off" />
          </div>
          <div class="field">
            <span class="label-txt">Ansvarig</span>
            <div class="segment">
              <button type="button" class:on={todoAssignee === meId} onclick={() => (todoAssignee = meId)}>Du</button>
              {#if partnerId}
                <button type="button" class:on={todoAssignee === partnerId} onclick={() => (todoAssignee = partnerId)}>{nameOf($people, partnerId)}</button>
              {/if}
              <button type="button" class:on={todoAssignee === 'both'} onclick={() => (todoAssignee = 'both')}>Gemensamt</button>
              <button type="button" class:on={todoAssignee === null} onclick={() => (todoAssignee = null)}>Ingen</button>
            </div>
          </div>
          <div class="row" style="gap:0.5rem;align-items:flex-end">
            <div class="field" style="flex:1">
              <label for="t-start">Från (valfritt)</label>
              <input id="t-start" class="input" type="date" bind:value={todoStart} />
            </div>
            <div class="field" style="flex:1">
              <label for="t-due">Deadline (valfritt)</label>
              <input id="t-due" class="input" type="date" bind:value={todoDue} />
            </div>
          </div>
          <p class="muted" style="font-size:0.78rem;margin:-0.4rem 0 0.8rem">
            Med både från + deadline blir det en period ("gör inom") – den dyker upp på Hem på sista dagen.
          </p>
          {#if todoError}<p class="error-text">{todoError}</p>{/if}
          <button class="btn btn-primary btn-block" type="submit" disabled={!todoTitle.trim()}>Lägg till</button>
        </form>
      {:else if $createKind === 'event'}
        <h3 style="padding:0 0.5rem 0.5rem">Nytt event</h3>
        <EventForm submitLabel="Skapa" onsubmit={submitEvent} />
      {/if}
    </div>
  </div>
{/if}

<style>
  .label-txt {
    font-size: 0.85rem;
    font-weight: 600;
    color: var(--muted);
  }
  .segment {
    display: flex;
    gap: 0.35rem;
    flex-wrap: wrap;
  }
  .segment button {
    flex: 1;
    min-width: 60px;
    border: 1px solid var(--border);
    background: var(--surface);
    color: var(--muted);
    border-radius: var(--radius-sm);
    padding: 0.5rem 0.4rem;
    font-size: 0.85rem;
    font-weight: 600;
  }
  .segment button.on {
    background: var(--accent);
    color: #fff;
    border-color: var(--accent);
  }
</style>
