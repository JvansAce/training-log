/* ============================================================
   WHOOP — reads today's recovery, strain and sleep through
   /api/whoop/*, which Cloudflare Access has already authenticated.
   Nothing in the browser ever talks to WHOOP directly or sees a
   token; the Worker holds those.
   ============================================================ */

const Whoop = (() => {
  let cache = null;      // last response we're confident showing
  let fetchedAt = 0;
  const STALE_MS = 10 * 60 * 1000; // recovery/strain update at most a few times a day

  async function today(force = false){
    if (!force && cache && Date.now() - fetchedAt < STALE_MS) return cache;
    try{
      const res = await fetch('/api/whoop/today', { cache: 'no-store' });
      const type = res.headers.get('content-type') || '';
      // Non-JSON here usually means an Access login page, not real data —
      // treat it the same as "couldn't reach it" rather than parsing HTML.
      if (!res.ok || !type.includes('application/json')){
        cache = cache || { connected: false, reason: 'unavailable' };
        return cache;
      }
      cache = await res.json();
      fetchedAt = Date.now();
      return cache;
    }catch(e){
      cache = cache || { connected: false, reason: 'unavailable' };
      return cache;
    }
  }

  /* WHOOP's own recovery bands. */
  function band(score){
    if (score == null) return '';
    if (score >= 67) return 'good';
    if (score >= 34) return 'mid';
    return 'low';
  }

  function connect(){ location.href = '/api/whoop/authorize'; }

  async function disconnect(){
    try{ await fetch('/api/whoop/disconnect', { method: 'POST' }); }catch(e){ /* proceed anyway */ }
    // A definite "not connected" state, not null — null reads as "still
    // checking" to the UI, which would show a spinner instead of the
    // Connect button right after someone just disconnected.
    cache = { connected: false, reason: 'not_connected' };
    fetchedAt = 0;
  }

  return { today, band, connect, disconnect, peek: () => cache };
})();
