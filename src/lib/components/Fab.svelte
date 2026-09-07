<script lang="ts">
  import { createKind } from '$lib/client/stores';
</script>

<!-- Själva sheeten renderas i CreateSheets (layouten): bottom-nav har transform,
     så en position:fixed-sheet här skulle positioneras mot naven, inte skärmen. -->
<button class="fab" aria-label="Lägg till" onclick={() => createKind.set('menu')}>
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round">
    <path d="M12 5v14M5 12h14" />
  </svg>
</button>
