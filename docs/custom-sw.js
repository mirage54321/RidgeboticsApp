// This is the registered worker for match alerts. Do not import Flutter's
// generated worker here: recent Flutter builds make that worker unregister
// itself, which also removed this push worker on iPhone.

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
    icon: data.icon || 'icons/Icon-200.png',
    badge: data.badge || 'icons/Icon-200.png',
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
