<script lang="ts">
  import { page } from '$app/stores';
  import { base } from '$app/paths';
  import Fab from './Fab.svelte';

  // Sökväg relativt basen (GitHub Pages serverar under /HouseMates)
  const rel = $derived($page.url.pathname.slice(base.length) || '/');

  function isActive(href: string, exact: boolean, path: string): boolean {
    return exact ? path === href : path.startsWith(href);
  }
</script>

<nav class="bottom-nav" aria-label="Huvudmeny">
  <a class="nav-item" class:active={isActive('/', true, rel)} href={base || '/'}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M3 10.5 12 3l9 7.5" /><path d="M5 9.5V21h14V9.5" />
    </svg>
    Hem
  </a>
  <a class="nav-item" class:active={isActive('/kalender', false, rel)} href="{base}/kalender">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <rect x="3" y="4.5" width="18" height="16" rx="2.5" /><path d="M3 9h18M8 3v3M16 3v3" />
    </svg>
    Kalender
  </a>

  <div style="position:relative"><Fab /></div>

  <a class="nav-item" class:active={isActive('/inkop', false, rel)} href="{base}/inkop">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <path d="M4 5h2l1.5 11h10L20 8H6.5" /><circle cx="9" cy="20" r="1.4" /><circle cx="17" cy="20" r="1.4" />
    </svg>
    Inköp
  </a>
  <a class="nav-item" class:active={isActive('/todo', false, rel)} href="{base}/todo">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
      <rect x="4" y="4" width="16" height="16" rx="3" /><path d="m8.5 12 2.5 2.5L16 9" />
    </svg>
    Att göra
  </a>
</nav>
