import { sveltekit } from '@sveltejs/kit/vite';
import { SvelteKitPWA } from '@vite-pwa/sveltekit';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [
    sveltekit(),
    SvelteKitPWA({
      registerType: 'autoUpdate',
      // Egen SW (push + offline) via injectManifest, se src/service-worker.ts.
      strategies: 'injectManifest',
      // SW körs inte i dev (undviker cache-krockar med SSR-auth); testas via
      // `npm run build && npm run preview`.
      devOptions: { enabled: false, type: 'module' },
      injectManifest: {
        globPatterns: ['**/*.{js,css,html,ico,png,svg,webmanifest}']
      },
      manifest: {
        name: 'Planeraren',
        short_name: 'Planeraren',
        start_url: '/',
        display: 'standalone',
        background_color: '#f5f3ef',
        theme_color: '#f5f3ef',
        icons: [
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png' }
        ]
      }
    })
  ],
  // Vitest-config. `test` typas via vitest, inte vite – därav @ts-expect-error.
  // (vitest 2 buntar en annan vite-version än projektets vite 6, så en
  //  triple-slash-referens räcker inte för att slå ihop typerna.)
  // @ts-expect-error – 'test' finns inte på vites UserConfig-typ
  test: {
    include: ['tests/**/*.test.ts'],
    passWithNoTests: true
  }
});
