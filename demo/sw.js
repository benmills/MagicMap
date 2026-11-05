// The page's cache, for a repeat visit or a return to a place: tiles (their game build in the address, so a tile once
// fetched never changes: kept for good, the oldest dropped past MAX_TILES), answered from here; the ocean, the whole-map
// stand-in (sea/) and the icons answered from the last visit at once while a fresh copy is fetched for the next.
// The page, its scripts and the API always go to the network (they change with a deploy).
const TILES = "mm-tiles-v1", SEA = "mm-sea-v1", MAX_TILES = 6000, TRIM_EVERY = 250;
let puts = 0;

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) =>
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== TILES && k !== SEA) await caches.delete(k);
    await self.clients.claim();
  })()),
);

async function trim() {
  const cache = await caches.open(TILES), keys = await cache.keys();
  for (const k of keys.slice(0, Math.max(0, keys.length - MAX_TILES))) await cache.delete(k); // (oldest first)
}

async function kept(request) {
  const cache = await caches.open(TILES), hit = await cache.match(request);
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok) {
    cache.put(request, response.clone()).catch(() => {});
    if (++puts % TRIM_EVERY === 0) trim().catch(() => {});
  }
  return response;
}

async function fresh(event) {
  const cache = await caches.open(SEA), hit = await cache.match(event.request, { ignoreSearch: true });
  const update = fetch(event.request).then((response) => {
    if (response.ok) cache.put(event.request, response.clone()).catch(() => {});
    return response;
  });
  if (hit) {
    event.waitUntil(update.catch(() => {}));
    return hit;
  }
  return update;
}

self.addEventListener("fetch", (event) => {
  const { request } = event, u = new URL(request.url);
  if (request.method !== "GET" || u.origin !== location.origin) return;
  if (u.pathname.startsWith("/tiles/") && u.searchParams.has("v")) event.respondWith(kept(request));
  else if (u.pathname.startsWith("/sea/") || u.pathname.startsWith("/icons/")) event.respondWith(fresh(event));
});
