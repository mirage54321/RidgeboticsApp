// This file replaces flutter_service_worker.js as the *registered* service
// worker. It imports Flutter's real service worker first (so you keep all
// of Flutter's normal web-app caching), then adds push notification
// handling on top.
//
// IMPORTANT: this file must live in your `web/` folder so it gets copied
// into `build/web/` on every `flutter build web`.

importScripts('flutter_service_worker.js');

self.addEventListener('push', function (event) {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (e) {
    // ignore malformed payloads
  }
  const title = data.title || 'Match starting soon';
  const options = {
    body: data.body || '',
    icon: data.icon || 'icons/Icon-192.png',
    badge: data.badge || 'icons/Icon-192.png',
    data: { url: data.url || '/' },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(event.notification.data.url || '/');
      }
    })
  );
});