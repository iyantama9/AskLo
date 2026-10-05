(() => {
  if (!('serviceWorker' in navigator)) return;

  window.addEventListener('load', () => {
    navigator.serviceWorker
      .getRegistrations()
      .then((registrations) => Promise.all(registrations.map((registration) => registration.unregister())))
      .then(() => {
        if (!window.caches) return null;
        return caches.keys().then((keys) => Promise.all(keys.map((key) => caches.delete(key))));
      })
      .catch(() => {});
  });
})();
