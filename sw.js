const CACHE='chess-battle-v19';
const CORE=['./','./index.html','./manifest.json','./icon-192.png','./apple-touch-icon.png','https://cdnjs.cloudflare.com/ajax/libs/peerjs/1.5.4/peerjs.min.js'];
const CACHEABLE=/^(https:\/\/(cdnjs\.cloudflare\.com|fonts\.googleapis\.com|fonts\.gstatic\.com)\/)/;
self.addEventListener('install',e=>{e.waitUntil(caches.open(CACHE).then(c=>Promise.allSettled(CORE.map(u=>c.add(u)))).then(()=>self.skipWaiting()))});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener('fetch',e=>{
  const r=e.request;if(r.method!=='GET')return;
  const url=r.url,same=url.startsWith(self.location.origin);
  if(r.mode==='navigate'){
    e.respondWith(fetch(r).then(res=>{const copy=res.clone();caches.open(CACHE).then(c=>c.put('./index.html',copy));return res}).catch(()=>caches.match('./index.html')));
    return;
  }
  if(!same&&!CACHEABLE.test(url))return;
  e.respondWith(caches.match(r).then(hit=>hit||fetch(r).then(res=>{if(res&&(res.ok||res.type==='opaque')){const copy=res.clone();caches.open(CACHE).then(c=>c.put(r,copy))}return res})));
});
