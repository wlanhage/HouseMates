<script lang="ts">
  import { createKind, online } from '$lib/client/stores';
  import { createShopping, createTodo, createChore, createEventAction, type EventInput } from '$lib/client/data';
  import EventForm from './EventForm.svelte';
  import AssigneePicker from './AssigneePicker.svelte';
  import { sheetDrag } from '$lib/client/sheetDrag';

  // Inköp
  let shopName = $state('');
  let shopQty = $state('');
  // Todo
  let todoTitle = $state('');
  let todoNotes = $state('');
  let todoAssignee = $state<string | null>('both');
  let todoStart = $state('');
  let todoDue = $state('');
  let todoError = $state('');
  // Städ
  let choreTitle = $state('');
  let choreAssignee = $state<string | null>('both');

  let firstField: HTMLInputElement | undefined = $state();

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
      todoAssignee = 'both';
      todoStart = '';
      todoDue = '';
      todoError = '';
    } else if (kind === 'chore') {
      choreTitle = '';
      choreAssignee = 'both';
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

  async function submitChore(e: Event) {
    e.preventDefault();
    if (!choreTitle.trim()) return;
    await createChore({ title: choreTitle, assignee: choreAssignee });
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
    <div class="sheet" role="dialog" aria-modal="true" aria-label="Skapa nytt" use:sheetDrag={close}>
      <div class="sheet-handle"></div>

      {#if $createKind === 'menu'}
        <button class="sheet-item" disabled={!$online} onclick={() => createKind.set('event')}>
          <span class="sheet-icon">📅</span>
          <span>
            Nytt event
            {#if !$online}<span class="muted" style="font-weight:400"> · kräver anslutning</span>{/if}
          </span>
        </button>
        <button class="sheet-item" onclick={() => createKind.set('shopping')}>
          <span class="sheet-icon">🛒</span>
          <span>Ny vara</span>
        </button>
        <button class="sheet-item" onclick={() => createKind.set('todo')}>
          <span class="sheet-icon">✅</span>
          <span>Ny uppgift</span>
        </button>
        <button class="sheet-item" onclick={() => createKind.set('chore')}>
          <span class="sheet-icon">🧽</span>
          <span>Ny städsyssla</span>
        </button>
      {:else if $createKind === 'shopping'}
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
            <span class="label-txt">Vem gör det?</span>
            <AssigneePicker bind:value={todoAssignee} allowNone />
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
      {:else if $createKind === 'chore'}
        <h3 style="padding:0 0.5rem 0.5rem">Ny städsyssla</h3>
        <form onsubmit={submitChore} style="padding:0 0.5rem">
          <div class="field">
            <label for="ch-title">Syssla</label>
            <input id="ch-title" bind:this={firstField} class="input" bind:value={choreTitle} placeholder="t.ex. Byta sängkläder" autocomplete="off" />
          </div>
          <div class="field">
            <span class="label-txt">Vem gör det?</span>
            <AssigneePicker bind:value={choreAssignee} allowNone />
          </div>
          <p class="muted" style="font-size:0.78rem;margin:-0.4rem 0 0.8rem">
            Bockas av gång på gång – listan visar när det gjordes senast och av vem.
          </p>
          <button class="btn btn-primary btn-block" type="submit" disabled={!choreTitle.trim()}>Lägg till</button>
        </form>
      {:else if $createKind === 'event'}
        <h3 style="padding:0 0.5rem 0.5rem">Nytt event</h3>
        <EventForm submitLabel="Skapa" onsubmit={submitEvent} />
      {/if}
    </div>
  </div>
{/if}
