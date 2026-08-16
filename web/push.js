// web/push.js
// Small JS bridge Dart calls into via dart:js_util. Registers our custom
// service worker (see custom-sw.js) and handles the actual PushManager
// subscription flow, which isn't exposed to Dart directly.

window.matchPush = (function () {
  let swRegistration = null;

  function urlBase64ToUint8Array(base64String) {
    const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
    const rawData = window.atob(base64);
    const outputArray = new Uint8Array(rawData.length);
    for (let i = 0; i < rawData.length; ++i) {
      outputArray[i] = rawData.charCodeAt(i);
    }
    return outputArray;
  }

  async function ensureRegistered() {
    if (!swRegistration) {
      swRegistration = await navigator.serviceWorker.register('custom-sw.js');
    }
    return swRegistration;
  }

  async function isSupported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  async function subscriptionState() {
    if (!(await isSupported())) return 'unsupported';
    await ensureRegistered();
    const sub = await swRegistration.pushManager.getSubscription();
    return sub ? 'subscribed' : 'unsubscribed';
  }

  async function subscribe(vapidPublicKey, teamNumber, eventKey, backendBase) {
    if (!(await isSupported())) return false;
    await ensureRegistered();
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') return false;
    let sub = await swRegistration.pushManager.getSubscription();
    if (!sub) {
      sub = await swRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(vapidPublicKey),
      });
    }
    const res = await fetch(`${backendBase}/push/subscribe`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ teamNumber, eventKey, subscription: sub.toJSON() }),
    });
    return res.ok;
  }

  async function unsubscribe(backendBase) {
    await ensureRegistered();
    const sub = await swRegistration.pushManager.getSubscription();
    if (!sub) return true;
    try {
      await fetch(`${backendBase}/push/unsubscribe`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ endpoint: sub.endpoint }),
      });
    } catch (e) {
      // still unsubscribe locally even if the backend call fails
    }
    await sub.unsubscribe();
    return true;
  }

  return { isSupported, subscriptionState, subscribe, unsubscribe };
})();