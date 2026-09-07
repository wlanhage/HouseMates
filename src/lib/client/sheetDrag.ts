/**
 * Dra-för-att-stänga på bottensheets (Svelte-action på .sheet-elementet).
 * Dra i handtaget: sheeten följer fingret. Släpp en bit ner eller med fart
 * så stängs den, annars fjädrar den tillbaka.
 */
const CLOSE_DISTANCE = 90; // px
const CLOSE_SPEED = 0.5; // px/ms

export function sheetDrag(node: HTMLElement, onclose: () => void) {
  const handle = node.querySelector<HTMLElement>('.sheet-handle');
  if (!handle) return;

  let active = false;
  let startY = 0;
  let startT = 0;
  let dy = 0;

  function down(e: PointerEvent) {
    active = true;
    startY = e.clientY;
    startT = performance.now();
    dy = 0;
    try {
      handle!.setPointerCapture(e.pointerId);
    } catch {
      /* syntetiska pekare saknar ibland capture – draget fungerar ändå */
    }
    node.style.transition = 'none';
  }

  function move(e: PointerEvent) {
    if (!active) return;
    dy = Math.max(0, e.clientY - startY);
    node.style.transform = `translateY(${dy}px)`;
  }

  function up() {
    if (!active) return;
    active = false;
    const speed = dy / Math.max(1, performance.now() - startT);
    if (dy > CLOSE_DISTANCE || speed > CLOSE_SPEED) {
      node.style.transition = 'transform 0.18s ease-in';
      node.style.transform = 'translateY(110%)';
      setTimeout(onclose, 160);
    } else {
      node.style.transition = 'transform 0.25s cubic-bezier(0.2, 0.9, 0.3, 1)';
      node.style.transform = '';
    }
  }

  handle.addEventListener('pointerdown', down);
  handle.addEventListener('pointermove', move);
  handle.addEventListener('pointerup', up);
  handle.addEventListener('pointercancel', up);

  return {
    destroy() {
      handle!.removeEventListener('pointerdown', down);
      handle!.removeEventListener('pointermove', move);
      handle!.removeEventListener('pointerup', up);
      handle!.removeEventListener('pointercancel', up);
    }
  };
}
