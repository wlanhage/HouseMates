import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    // Ren SPA: all data går via Supabase, ingen egen server.
    adapter: adapter({ fallback: 'index.html' }),
    paths: {
      // GitHub Pages serverar under /HouseMates – sätts vid bygge.
      base: process.env.BASE_PATH || ''
    },
    serviceWorker: {
      // Registreras via @vite-pwa/sveltekit istället
      register: false
    }
  }
};

export default config;
