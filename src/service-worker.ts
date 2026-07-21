/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />
/**
 * Egen service worker (injectManifest, spec §12.3 + §11):
 *  - precachar appskalet
 *  - NetworkFirst för navigeringar (online → SSR/auth; offline → cache)
 *  - push-notiser + notisklick öppnar Hem
 */
import { precacheAndRoute } from 'workbox-precaching';
import { NavigationRoute, registerRoute } from 'workbox-routing';
import { NetworkFirst } from 'workbox-strategies';

const sw = self as unknown as ServiceWorkerGlobalScope;

// injectManifest ersätter self.__WB_MANIFEST i det byggda SW:t.
precacheAndRoute(
  (self as unknown as { __WB_MANIFEST: Array<{ url: string; revision: string | null }> })
    .__WB_MANIFEST
);

// Navigeringar: NetworkFirst, men aldrig /api.
registerRoute(
  new NavigationRoute(new NetworkFirst({ cacheName: 'pages', networkTimeoutSeconds: 3 }), {
    denylist: [/^\/api\//]
  })
);
// SvelteKit-data: NetworkFirst.
registerRoute(
  ({ url }) => url.pathname.includes('__data.json'),
  new NetworkFirst({ cacheName: 'sveltekit-data', networkTimeoutSeconds: 3 })
);

sw.addEventListener('push', (event) => {
  let data: { title: string; body: string } = { title: 'Planeraren', body: '' };
  try {
    if (event.data) data = { ...data, ...(event.data.json() as Partial<typeof data>) };
  } catch {
    /* ogiltig payload – visa standardtitel */
  }
  event.waitUntil(
    sw.registration.showNotification(data.title, {
      body: data.body,
      icon: '/icons/icon-192.png',
      badge: '/icons/icon-192.png',
      data: { url: '/' }
    })
  );
});

sw.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    (async () => {
      const all = await sw.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of all) {
        await (client as WindowClient).focus();
        return;
      }
      await sw.clients.openWindow('/');
    })()
  );
});

sw.addEventListener('install', () => sw.skipWaiting());
sw.addEventListener('activate', (event) => event.waitUntil(sw.clients.claim()));

export {};
