<script lang="ts">
  let {
    color = '#6b7280',
    initial = '?',
    size = 24
  }: { color?: string; initial?: string; size?: number } = $props();
</script>

<span
  class="avatar"
  style={`background:${color};width:${size}px;height:${size}px;font-size:${Math.round(size * 0.42)}px`}
  aria-hidden="true">{initial}</span>
