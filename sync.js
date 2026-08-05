/* ============================================================
   Sync — talks to /api/state, which Cloudflare Access has already
   authenticated. localStorage stays the local source of truth so the
   app works with no signal; pushes happen opportunistically and the
   server merges, so two devices converge instead of overwriting.
   ============================================================ */

const Sync = (() => {
  const ENDPOINT = '/api/state';
  const SYNCED_KEY = 'bnb.synced.v1';
  let status = 'idle';   // idle | syncing | ok | offline | unauthorized | unconfigured | absent
  let lastAt = null;
  let detail = '';
  let timer = null;
  const listeners = [];

  const set = (s, d = '') => {
    status = s; detail = d;
    if (s === 'ok') lastAt = new Date();
    listeners.forEach(fn => fn(state()));
  };
  const state = () => ({ status, lastAt, detail, available: status !== 'absent' && status !== 'unconfigured' });

  function label(){
    switch (status){
      case 'syncing':      return 'SYNCING…';
      case 'ok':           return `SYNCED ${lastAt.toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'})}`;
      case 'offline':      return 'OFFLINE · CHANGES PENDING';
      case 'unauthorized': return 'SIGN IN AGAIN TO SYNC';
      case 'unconfigured': return 'SYNC NOT CONFIGURED';
      case 'absent':       return 'LOCAL ONLY';
      default:             return 'NOT SYNCED YET';
    }
  }

  /* A device with no real history should pull rather than push, so its
     empty defaults never dilute the stored record. */
  const isFresh = s =>
    Object.keys(s.logs || {}).length === 0 &&
    Object.keys(s.lifts || {}).length === 0 &&
    (s.weights || []).length <= 1;

  async function call(method, body){
    const res = await fetch(ENDPOINT, {
      method,
      cache: 'no-store',
      headers: body ? { 'content-type': 'application/json' } : undefined,
      body: body ? JSON.stringify(body) : undefined
    });
    if (res.status === 404) { set('absent'); return null; }
    if (res.status === 401 || res.status === 403) { set('unauthorized'); return null; }
    if (res.status === 503) {
      const j = await res.json().catch(() => ({}));
      set('unconfigured', j.error || ''); return null;
    }
    if (!res.ok) {
      const j = await res.json().catch(() => ({}));
      set('offline', j.error || `HTTP ${res.status}`); return null;
    }
    // An Access login page is HTML, not JSON — treat that as a lapsed session.
    const type = res.headers.get('content-type') || '';
    if (!type.includes('application/json')) { set('unauthorized'); return null; }
    return res.json();
  }

  const hasSyncedBefore = () => { try{ return !!localStorage.getItem(SYNCED_KEY); }catch(e){ return false; } };
  const markSynced = () => { try{ localStorage.setItem(SYNCED_KEY, '1'); }catch(e){} };

  /* Returns merged state to adopt, or null if nothing to adopt.

     Deliberately does NOT bail out early when status is already 'absent' or
     'unconfigured' — those are set by the previous attempt's response, not
     a permanent fact. Without a retry path, a device that first tries to
     sync while a deploy is mid-flight gets stuck reporting "sync not
     configured" for the rest of the page session, even after the deploy
     finishes and the server would happily answer now. Every call below
     re-derives status from what actually comes back. */
  async function run(local){
    if (!navigator.onLine) { set('offline'); return null; }
    set('syncing');
    try{
      // A device with no confirmed sync history can't trust its own
      // updatedAt to safely win a same-day "newer wins" merge — it has no
      // way to know whether the ticks it already has are the ONLY record of
      // today, or a partial one alongside real history sitting on the
      // server. So the very first sync always pulls, never pushes.
      const neverSynced = !hasSyncedBefore();
      if (neverSynced || isFresh(local)){
        const startUpdatedAt = local.updatedAt || 0;
        const out = await call('GET');
        if (!out) return null;
        set('ok');
        markSynced();
        if (!out.state) return null;
        // If a checkbox got ticked locally while this pull was in flight,
        // don't blindly overwrite it with the (now stale) server copy —
        // that edit's own save() already queued a follow-up push, and by
        // then the server has a real baseline to merge against.
        if ((local.updatedAt || 0) !== startUpdatedAt) return null;
        return out.state;
      }
      const out = await call('PUT', local);
      if (!out) return null;
      set('ok');
      markSynced();
      return out.state || null;
    }catch(e){
      /* Network exceptions carry no message worth showing. */
      set('offline');
      return null;
    }
  }

  function schedule(getLocal, adopt, ms = 2500){
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const merged = await run(getLocal());
      if (merged) adopt(merged);
    }, ms);
  }

  return {
    run, schedule, label, state,
    onChange: fn => listeners.push(fn),
    // Always clears to 'idle' — see the comment on run() for why 'absent'/
    // 'unconfigured' must not be sticky. This just clears the last-known
    // status; run() decides the real one from the next actual response.
    reset: () => set('idle')
  };
})();
