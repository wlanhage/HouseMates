<script lang="ts">
  import { user, me } from '$lib/client/stores';
  import { people, nameOf, colorOf } from '$lib/client/people';

  /** Väljare "för vem": du / partnern / båda (+ ingen). Vald knapp får personens färg. */
  let {
    value = $bindable(null),
    allowNone = false
  }: { value?: string | null; allowNone?: boolean } = $props();

  const meId = $derived($user?.id ?? null);
  const partnerId = $derived($me?.partner?.id ?? null);

  const options = $derived<{ id: string | null; label: string }[]>([
    ...(meId ? [{ id: meId, label: 'Du' }] : []),
    ...(partnerId ? [{ id: partnerId, label: nameOf($people, partnerId) }] : []),
    { id: 'both', label: 'Båda' },
    ...(allowNone ? [{ id: null, label: 'Ingen' }] : [])
  ]);

  function styleFor(id: string | null): string {
    if (value !== id || !id) return '';
    const c = colorOf($people, id);
    return `background:${c};border-color:${c};color:#fff`;
  }
</script>

<div class="segment" role="group" aria-label="För vem">
  {#each options as o (o.id ?? 'none')}
    <button type="button" class:on={value === o.id} style={styleFor(o.id)} onclick={() => (value = o.id)}>
      {o.label}
    </button>
  {/each}
</div>

<style>
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
    transition: background 0.15s, color 0.15s, border-color 0.15s;
  }
  .segment button.on {
    background: var(--accent);
    color: #fff;
    border-color: var(--accent);
  }
</style>
