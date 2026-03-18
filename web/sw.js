const CACHE_NAME = 'hydra-bin-v4';
const OFFLINE_URL = '/offline.html';

// Core assets to pre-cache
const PRECACHE_ASSETS = [
  '/',
  '/index.html',
  '/offline.html',
  '/manifest.json',
  '/flutter_bootstrap.js',
];

// ── Install: pre-cache core assets ────────────────────────────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(PRECACHE_ASSETS).catch(() => {
        return cache.addAll(['/index.html', '/offline.html']);
      });
    }).then(() => self.skipWaiting())
  );
});

// ── Activate: clean up old caches ─────────────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => Promise.all(
      keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k))
    )).then(() => self.clients.claim())
  );
});

// ── Fetch: Stale-While-Revalidate ─────────────────────────────────────────────
self.addEventListener('fetch', event => {
  const req = event.request;

  // Only handle GET requests
  if (req.method !== 'GET') return;

  // Skip Firebase, analytics, and external APIs (always go network)
  const url = new URL(req.url);
  if (url.hostname.includes('firestore.googleapis.com') ||
      url.hostname.includes('firebase') ||
      url.hostname.includes('googleapis.com') ||
      url.hostname.includes('google.com') ||
      url.hostname.includes('gravatar.com') ||
      url.hostname.includes('roblox.com') ||
      url.hostname.includes('corsproxy.io')) {
    return;
  }

  event.respondWith(
    caches.open(CACHE_NAME).then(cache => {
      return cache.match(req).then(cachedResponse => {
        const networkFetch = fetch(req).then(networkResponse => {
          if (networkResponse && networkResponse.status === 200) {
            cache.put(req, networkResponse.clone());
          }
          return networkResponse;
        }).catch(() => null);

        if (cachedResponse) {
          networkFetch; // fire and forget
          return cachedResponse;
        }

        return networkFetch.then(response => {
          if (response) return response;
          if (req.mode === 'navigate') {
            return cache.match(OFFLINE_URL) || new Response('Offline', { status: 503 });
          }
          return new Response('', { status: 503 });
        });
      });
    })
  );
});

// ── Push Notifications ────────────────────────────────────────────────────────
self.addEventListener('push', event => {
  if (!event.data) return;
  let data = {};
  try { data = event.data.json(); } catch (_) { data = { title: 'Hydra Bin', body: event.data.text() }; }

  const title = data.title || 'Hydra Bin';
  const options = {
    body: data.body || 'You have a new notification.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.tag || 'hydra-bin-notification',
    renotify: true,
    vibrate: [200, 100, 200],
    data: { url: data.url || '/' },
    actions: data.actions || [],
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

// ── Notification Click: open/focus the app ────────────────────────────────────
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clientList => {
      for (const client of clientList) {
        if (client.url === targetUrl && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
