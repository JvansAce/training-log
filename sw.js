/* Cache-first shell so the app works offline in the gym.
   Bump CACHE when you change any file. */
const CACHE = 'bnb-v28';
const ASSETS = ['./','./index.html','./app.css','./app.js','./sync.js','./whoop.js',
  './manifest.webmanifest','./icon.svg','./icon-192.png','./icon-512.png'];

self.addEventListener('install', e => {
  // No self.skipWaiting() here — the new worker sits in "waiting" until the
  // page explicitly tells it to take over (see the SKIP_WAITING message
  // below). Activating instantly used to swap the running app out from
  // under someone mid-session with no warning that anything had changed.
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(ASSETS)));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys()
    .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener('message', e => {
  if (e.data === 'SKIP_WAITING') self.skipWaiting();
  // Lets the page ask a worker which version it is. Without this the page
  // can only read Cache Storage, which during a pending update contains
  // both the running version and the incoming one and cannot tell them
  // apart — so it could not know whether an "update" was real.
  if (e.data === 'VERSION' && e.ports && e.ports[0]) e.ports[0].postMessage(CACHE);
});
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const u = new URL(e.request.url);
  // Access endpoints and the sync API must always hit the network. Cross-
  // origin requests (Google Fonts) are left alone entirely — intercepting
  // them here meant a network failure returned this app's own index.html
  // in place of a stylesheet/font, and the origin check below couldn't
  // save it because it compared against the wrong URL after a redirect.
  if (u.origin !== location.origin) return;
  if (u.pathname.startsWith('/cdn-cgi/') || u.pathname.startsWith('/api/')) return;

  // Navigations go to the network FIRST, falling back to the cached shell
  // when it fails. Serving them cache-first meant the page always loaded
  // without touching the network, so when an Access session expired there
  // was never a navigation for Access to redirect to its login page — the
  // app just sat there with every API call throwing and no route back to
  // signing in. Offline in the gym still works: that's the catch below.
  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request).then(res => {
        // An opaqueredirect (type 'opaqueredirect', status 0) is Access
        // sending us to the login page. Hand it straight back so the
        // browser follows it, and don't try to cache it.
        if (res.ok && res.type === 'basic') {
          caches.open(CACHE).then(c => c.put('./index.html', res.clone()));
        }
        return res;
      }).catch(() =>
        caches.match('./index.html').then(hit => hit || caches.match('./')))
    );
    return;
  }

  e.respondWith(
    caches.match(e.request).then(hit => hit || fetch(e.request).then(res => {
      // A lapsed Access session can come back same-origin with a 200 and
      // HTML content, redirected or not — caching that under a JS/CSS
      // request's key would serve a login page as app code forever after.
      const ct = res.headers.get('content-type') || '';
      const expectHtml = e.request.mode === 'navigate' || u.pathname === '/' || u.pathname.endsWith('.html');
      const looksRight = expectHtml || !ct.includes('text/html');
      if (res.ok && !res.redirected && looksRight) {
        caches.open(CACHE).then(c => c.put(e.request, res.clone()));
      }
      return res;
    }).catch(() => e.request.mode === 'navigate' ? caches.match('./index.html') : Response.error()))
  );
});
