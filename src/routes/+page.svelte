<script lang="ts">
  import { onMount } from 'svelte';
  import { user, todosOpen, activity, events } from '$lib/client/stores';
  import { people, colorOf, initialOf, nameOf } from '$lib/client/people';
  import { refreshTodos, refreshActivity, refreshEvents, setTodoDone } from '$lib/client/data';
  import { todayStr, tomorrowStr, relativeTime, dueLabel, hhmm } from '$lib/client/dates';
  import { eventSpan } from '$lib/client/agenda';
  import { groupActivity, describeGroup } from '$lib/client/activityFeed';
  import Avatar from '$lib/components/Avatar.svelte';
  import type { CalendarEvent } from '$lib/types';

  onMount(() => {
    void refreshTodos();
    void refreshActivity();
    void refreshEvents();
  });

  function eventsOnDay(day: string): CalendarEvent[] {
    return $events
      .filter((e) => {
        const s = eventSpan(e);
        return day >= s.first && day <= s.last;
      })
      .sort((a, b) =>
        a.allDay !== b.allDay ? (a.allDay ? -1 : 1) : a.allDay ? 0 : a.start.localeCompare(b.start)
      );
  }

  function greeting(): string {
    const h = new Date().getHours();
    if (h < 5) return 'God natt';
    if (h < 10) return 'God morgon';
    if (h < 18) return 'Hej';
    return 'God kväll';
  }

  const today = todayStr();
  const tomorrow = tomorrowStr();
  const afterSix = new Date().getHours() >= 18;

  // "Idag": försenade + dagens uppgifter (events tillkommer i M4).
  const todayTodos = $derived(
    $todosOpen
      .filter((t) => t.due_date && t.due_date <= today)
      .sort((a, b) => (a.due_date ?? '').localeCompare(b.due_date ?? ''))
  );
  const tomorrowTodos = $derived($todosOpen.filter((t) => t.due_date === tomorrow));
  const todayEvents = $derived(eventsOnDay(today));
  const tomorrowEvents = $derived(eventsOnDay(tomorrow));

  const groups = $derived(groupActivity($activity));

  const meName = $derived($user ? $user.name.replace(/\s*\(test\)/, '') : '');

  const dateLine = (() => {
    const s = new Intl.DateTimeFormat('sv-SE', {
      weekday: 'long',
      day: 'numeric',
      month: 'long'
    }).format(new Date());
    return s.charAt(0).toUpperCase() + s.slice(1);
  })();
</script>

<svelte:head><title>Hem</title></svelte:head>

<header class="hero">
  <h2>{greeting()}{meName ? `, ${meName}` : ''} 👋</h2>
  <p>{dateLine}</p>
</header>

<div class="section-title">Idag</div>
{#if todayEvents.length === 0 && todayTodos.length === 0}
  <div class="card empty">
    <span class="emoji">🌤️</span>
    Inget inplanerat idag.
  </div>
{:else}
  <div class="list">
    {#each todayEvents as e (e.id)}
      <div class="home-row">
        <span class="mini-dot" style={`background:${colorOf($people, e.createdBy)}`}></span>
        <span style="flex:1">{e.title}</span>
        <span class="muted" style="font-size:0.8rem;white-space:nowrap">
          {e.allDay ? 'Heldag' : hhmm(e.start)}
        </span>
      </div>
    {/each}
    {#each todayTodos as t (t.id)}
      {@const due = dueLabel(t.due_date!)}
      <div class="home-row">
        <button class="mini-check" aria-label="Bocka av" onclick={() => void setTodoDone(t, true)}></button>
        <span style="flex:1">{t.title}</span>
        <span class="badge badge-{due.kind}">{due.text}</span>
        {#if t.assignee}
          <Avatar color={colorOf($people, t.assignee)} initial={initialOf($people, t.assignee)} size={20} />
        {/if}
      </div>
    {/each}
  </div>
{/if}

{#if afterSix && (tomorrowEvents.length || tomorrowTodos.length)}
  <div class="section-title">Imorgon</div>
  <div class="list">
    {#each tomorrowEvents as e (e.id)}
      <div class="home-row">
        <span class="mini-dot" style={`background:${colorOf($people, e.createdBy)}`}></span>
        <span style="flex:1">{e.title}</span>
        <span class="muted" style="font-size:0.8rem;white-space:nowrap">
          {e.allDay ? 'Heldag' : hhmm(e.start)}
        </span>
      </div>
    {/each}
    {#each tomorrowTodos as t (t.id)}
      <div class="home-row">
        <span class="mini-dot" style={`background:${colorOf($people, t.assignee)}`}></span>
        <span style="flex:1">{t.title}</span>
      </div>
    {/each}
  </div>
{/if}

<div class="section-title">Nyligen</div>
{#if groups.length === 0}
  <div class="card empty">
    <span class="emoji">✨</span>
    Aktivitetsflödet visas här när ni börjar planera tillsammans.
  </div>
{:else}
  <div class="list">
    {#each groups as g (g.key)}
      <div class="home-row">
        <Avatar color={colorOf($people, g.actor)} initial={initialOf($people, g.actor)} size={26} />
        <span style="flex:1">
          <strong>{nameOf($people, g.actor, $user?.id)}</strong>
          {describeGroup(g)}
        </span>
        <span class="muted" style="font-size:0.78rem;white-space:nowrap">{relativeTime(g.newest)}</span>
      </div>
    {/each}
  </div>
{/if}

<style>
  .hero {
    margin: 0.5rem 0 1.1rem;
  }
  .hero h2 {
    font-size: 1.7rem;
    font-weight: 800;
    margin: 0;
  }
  .hero p {
    margin: 0.15rem 0 0;
    color: var(--muted);
    font-size: 0.92rem;
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
    transition: border-color 0.15s;
  }
  .mini-check:active {
    border-color: var(--ok);
  }
  .mini-dot {
    width: 9px;
    height: 9px;
    border-radius: 999px;
    flex: none;
  }
</style>
