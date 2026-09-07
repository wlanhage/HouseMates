<script lang="ts">
  import { sheetDrag } from '$lib/client/sheetDrag';
  /** Bekräftelse för oåterkalleliga val, i samma bottensheet-stil som skapa-formulären. */
  let {
    title,
    text = '',
    confirmLabel = 'Ta bort',
    onconfirm,
    oncancel
  }: {
    title: string;
    text?: string;
    confirmLabel?: string;
    onconfirm: () => void;
    oncancel: () => void;
  } = $props();
</script>

<svelte:window
  onkeydown={(e) => {
    if (e.key === 'Escape') oncancel();
  }}
/>

<div class="scrim">
  <button class="scrim-bg" aria-label="Avbryt" onclick={oncancel}></button>
  <div class="sheet" role="alertdialog" aria-modal="true" aria-label={title} use:sheetDrag={oncancel}>
    <div class="sheet-handle"></div>
    <div class="body">
      <h3>{title}</h3>
      {#if text}<p class="muted">{text}</p>{/if}
      <div class="row" style="gap:0.6rem">
        <button class="btn" style="flex:1" onclick={oncancel}>Avbryt</button>
        <button class="btn danger-fill" style="flex:1" onclick={onconfirm}>{confirmLabel}</button>
      </div>
    </div>
  </div>
</div>

<style>
  .body {
    padding: 0 0.5rem 0.5rem;
  }
  .body h3 {
    margin: 0 0 0.4rem;
    font-size: 1.15rem;
  }
  .body p {
    margin: 0 0 1rem;
    font-size: 0.9rem;
    line-height: 1.45;
  }
  .danger-fill {
    background: var(--danger);
    border-color: var(--danger);
    color: #fff;
    font-weight: 700;
  }
</style>
