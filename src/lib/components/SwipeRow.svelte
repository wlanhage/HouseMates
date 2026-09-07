<script lang="ts">
  import type { Snippet } from 'svelte';

  let {
    ontap,
    ondelete,
    children
  }: { ontap?: () => void; ondelete?: () => void; children: Snippet } = $props();

  const OPEN = 72; // px avslöjad radera-knapp
  let dx = $state(0);
  let open = $state(false);

  let startX = 0;
  let startY = 0;
  let mode = $state<'none' | 'h' | 'v'>('none');
  let moved = false;
  let longPress: ReturnType<typeof setTimeout> | undefined;
  // Tryck räknas bara på bockens yta ([data-tap]) när raden har en; annars hela raden.
  let tapAllowed = false;

  function down(e: PointerEvent) {
    startX = e.clientX;
    startY = e.clientY;
    mode = 'none';
    moved = false;
    const row = e.currentTarget as HTMLElement;
    tapAllowed = !row.querySelector('[data-tap]') || !!(e.target as Element).closest('[data-tap]');
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    // Långtryck avslöjar radera-knappen (spec §12.2: swipe ELLER långtryck).
    clearTimeout(longPress);
    longPress = setTimeout(() => {
      if (mode === 'none' && !moved) {
        open = true;
        dx = -OPEN;
      }
    }, 500);
  }

  function move(e: PointerEvent) {
    if (!(e.buttons & 1) && e.pointerType === 'mouse') return;
    const ddx = e.clientX - startX;
    const ddy = e.clientY - startY;
    if (mode === 'none') {
      if (Math.abs(ddx) < 6 && Math.abs(ddy) < 6) return;
      clearTimeout(longPress);
      mode = Math.abs(ddx) > Math.abs(ddy) ? 'h' : 'v';
    }
    if (mode !== 'h') return;
    moved = true;
    const base = open ? -OPEN : 0;
    dx = Math.max(-OPEN, Math.min(0, base + ddx));
  }

  function up(e: PointerEvent) {
    clearTimeout(longPress);
    if (mode === 'h') {
      open = dx < -OPEN / 2;
      dx = open ? -OPEN : 0;
    } else if (mode === 'none' && e.type === 'pointerup') {
      // Ett riktigt tryck: ingen rörelse, och inte en skroll som iOS avbröt (pointercancel).
      if (open) {
        open = false;
        dx = 0;
      } else if (tapAllowed) {
        ontap?.();
      }
    }
    mode = 'none';
  }

  function del() {
    open = false;
    dx = 0;
    ondelete?.();
  }
</script>

<div class="swipe">
  <button class="swipe-del" tabindex="-1" aria-label="Radera" onclick={del}>
    <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13h10l1-13" />
    </svg>
  </button>
  <div
    class="swipe-fg"
    style={`transform:translateX(${dx}px)`}
    class:animate={mode !== 'h'}
    role="button"
    tabindex="0"
    onpointerdown={down}
    onpointermove={move}
    onpointerup={up}
    onpointercancel={up}
    onkeydown={(e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        ontap?.();
      }
    }}
  >
    {@render children()}
  </div>
</div>

<style>
  .swipe {
    position: relative;
    border-radius: var(--radius-sm);
    overflow: hidden;
  }
  .swipe-del {
    position: absolute;
    top: 0;
    right: 0;
    bottom: 0;
    width: 72px;
    border: none;
    background: var(--danger);
    color: #fff;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .swipe-fg {
    position: relative;
    touch-action: pan-y;
    background: var(--surface);
    -webkit-user-select: none;
    user-select: none;
  }
  .swipe-fg.animate {
    transition: transform 0.18s ease;
  }
</style>
