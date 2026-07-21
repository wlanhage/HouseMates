<script lang="ts">
  import { toast, dismissToast } from '$lib/client/stores';

  function undo() {
    const t = $toast;
    dismissToast();
    t?.undo?.();
  }
</script>

{#if $toast}
  <div class="toast-host">
    <div class="toast" role="status">
      <span>{$toast.message}</span>
      {#if $toast.undo}
        <button onclick={undo}>Ångra</button>
      {/if}
    </div>
  </div>
{/if}
