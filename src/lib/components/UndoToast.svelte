<script lang="ts">
  import { toast, dismissToast } from '$lib/client/stores';

  function undo() {
    const t = $toast;
    dismissToast();
    t?.undo?.();
  }

  /** Svep toasten åt sidan eller nedåt för att ta bort den. */
  function swipeAway(node: HTMLElement) {
    let startX = 0;
    let startY = 0;
    let dx = 0;
    let dy = 0;
    let active = false;

    function down(e: PointerEvent) {
      if ((e.target as HTMLElement).closest('button')) return;
      active = true;
      startX = e.clientX;
      startY = e.clientY;
      dx = dy = 0;
      node.style.transition = 'none';
      try {
        node.setPointerCapture(e.pointerId);
      } catch {
        /* syntetiska pekare */
      }
    }
    function move(e: PointerEvent) {
      if (!active) return;
      dx = e.clientX - startX;
      dy = Math.max(0, e.clientY - startY);
      node.style.transform = `translate(${dx}px, ${dy}px)`;
      node.style.opacity = String(Math.max(0.35, 1 - (Math.abs(dx) + dy) / 220));
    }
    function up() {
      if (!active) return;
      active = false;
      if (Math.abs(dx) > 60 || dy > 40) {
        node.style.transition = 'transform 0.15s ease-in, opacity 0.15s';
        node.style.transform = `translate(${dx * 3}px, ${dy * 3}px)`;
        node.style.opacity = '0';
        setTimeout(dismissToast, 140);
      } else {
        node.style.transition = 'transform 0.2s cubic-bezier(0.2, 0.9, 0.3, 1), opacity 0.2s';
        node.style.transform = '';
        node.style.opacity = '';
      }
    }
    node.addEventListener('pointerdown', down);
    node.addEventListener('pointermove', move);
    node.addEventListener('pointerup', up);
    node.addEventListener('pointercancel', up);
    return {
      destroy() {
        node.removeEventListener('pointerdown', down);
        node.removeEventListener('pointermove', move);
        node.removeEventListener('pointerup', up);
        node.removeEventListener('pointercancel', up);
      }
    };
  }
</script>

{#if $toast}
  <div class="toast-host">
    {#key $toast.id}
      <div class="toast" role="status" use:swipeAway>
        <span>{$toast.message}</span>
        {#if $toast.undo}
          <button onclick={undo}>Ångra</button>
        {/if}
      </div>
    {/key}
  </div>
{/if}
