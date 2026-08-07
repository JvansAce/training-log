/* ============================================================
   GET  /api/state   → your stored state
   PUT  /api/state   → merge the body into stored state, return merged

   Identity comes from Cloudflare Access. The Cf-Access-Authenticated-User-Email
   header alone is not trusted: the Cf-Access-Jwt-Assertion token is verified
   against your team's public keys, so a request that somehow skipped Access
   cannot forge an identity.

   Bindings required (Pages project → Settings → Functions):
     DB                  D1 database
     ACCESS_TEAM_DOMAIN  yourteam.cloudflareaccess.com
     ACCESS_AUD          Application Audience tag from the Access app
   Local development only:
     DEV_EMAIL           skips verification, acts as this user
   ============================================================ */

import { identify, json } from '../_shared.js';

// Within this window, latest write wins rather than additive-union. 2 would
// match the client's own "recent" window exactly, but this runs in a Worker
// (UTC) while client dates are local calendar days — 3 absorbs that skew
// without needing to thread a timezone through every request.
const RECENT_DAYS = 3;
const MAX_BODY = 2_000_000;     // 2 MB ceiling on a pushed state, measured in bytes

/* ---------- merge ---------- */
// Works for both the numeric indices legacy clients still send and the
// string keys current ones do, including a mix of the two mid-migration.
const cmp = (p, q) => String(p) < String(q) ? -1 : String(p) > String(q) ? 1 : 0;
const daysAgo = n => {
  const d = new Date(); d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
};

/* Brand New Mind. Same philosophy as the body half: days are additive so
   nothing is lost, scalars take the higher/newer value, and journal text is
   never silently dropped — losing something someone typed is worse than
   keeping a stale copy of it. */
function mergeMind(ma, mb, newerMind, olderMind){
  const a = ma || {}, b = mb || {}, nw = newerMind || {}, od = olderMind || {};
  const out = {
    // Earliest start wins: whichever device began the programme did so on
    // one real date, and a later install must not reset the week counter.
    startDate: [a.startDate, b.startDate].filter(Boolean).sort()[0] ?? null,
    // Monotonic on both sides. These only ever climb by design, so max is
    // the merge — and it means a device that is behind cannot un-unlock a
    // practice the other one has been logging.
    unlocked : Math.max(a.unlocked  || 1, b.unlocked  || 1),
    ladderCap: Math.max(a.ladderCap || 1, b.ladderCap || 1),
    logs: {}, targets: {}, ladderLog: {}
  };

  const cutoff = daysAgo(RECENT_DAYS);
  const dates = new Set([...Object.keys(a.logs || {}), ...Object.keys(b.logs || {})]);
  for (const d of dates){
    const la = (a.logs || {})[d] || {}, lb = (b.logs || {})[d] || {};
    const pick = (nw.logs || {})[d] ?? (od.logs || {})[d] ?? {};
    if (d >= cutoff){
      out.logs[d] = {
        done: pick.done || [], mins: pick.mins || {},
        // Except the journal. An empty box on the newer device is far more
        // likely to be a device that never had the text than a deliberate
        // deletion, and a paragraph someone wrote is not worth that bet.
        journal: (pick.journal || '').trim() ? pick.journal : (la.journal || lb.journal || '')
      };
    } else {
      out.logs[d] = {
        done: [...new Set([...(la.done || []), ...(lb.done || [])])].sort(cmp),
        // Higher minutes wins: both sides saw the same sit, one just logged
        // it before it finished.
        mins: Object.fromEntries([...new Set([
          ...Object.keys(la.mins || {}), ...Object.keys(lb.mins || {})
        ])].map(k => [k, Math.max((la.mins || {})[k] || 0, (lb.mins || {})[k] || 0)])),
        journal: ((la.journal || '').length >= (lb.journal || '').length ? la.journal : lb.journal) || ''
      };
    }
  }

  // Targets climb, same as the loads they represent.
  for (const k of new Set([...Object.keys(a.targets || {}), ...Object.keys(b.targets || {})]))
    out.targets[k] = Math.max((a.targets || {})[k] || 0, (b.targets || {})[k] || 0);

  // A Saturday that happened, happened.
  for (const d of new Set([...Object.keys(a.ladderLog || {}), ...Object.keys(b.ladderLog || {})]))
    out.ladderLog[d] = (b.ladderLog || {})[d] ?? (a.ladderLog || {})[d];

  return out;
}

/* Additive by default so nothing is ever lost, but recent days take the
   latest write so that unticking something on the device in your hand
   actually sticks. */
export function mergeState(stored, incoming){
  const a = stored || {}, b = incoming || {};
  const newer = (b.updatedAt || 0) >= (a.updatedAt || 0) ? b : a;
  const older = newer === b ? a : b;
  const cutoff = daysAgo(RECENT_DAYS);

  // Spread both records first so any field neither side of this function
  // knows about (a future addition to the client's state shape) survives
  // the round trip instead of being silently dropped — then overwrite the
  // fields below with the real merge logic.
  const out = {
    ...older, ...newer,
    updatedAt : Math.max(a.updatedAt || 0, b.updatedAt || 0),
    startDate : newer.startDate  ?? older.startDate  ?? null,
    pyramidCap: newer.pyramidCap ?? older.pyramidCap ?? 6,
    calAdjust : newer.calAdjust  ?? older.calAdjust  ?? 0,
    // Scalars that only ever get set once. The spread above would carry
    // them anyway, but only from whichever record is "newer" — so a device
    // that has never been told the height would blank it on the first push
    // it happens to win. ?? across both sides keeps it. Anything else added
    // to this class of field belongs on this list too.
    heightCm  : newer.heightCm   ?? older.heightCm   ?? null,
    birthYear : newer.birthYear  ?? older.birthYear  ?? null,
    weights: [], waist: [], logs: {}, lifts: {}, whoop: {}, pyramidLog: {},
    mind: mergeMind(a.mind, b.mind, newer.mind, older.mind)
  };

  const byDate = (xs = [], ys = []) => {
    const m = new Map();
    xs.forEach(v => m.set(v.d, v));
    ys.forEach(v => m.set(v.d, v));   // same morning: newest push wins
    return [...m.values()].sort((x, y) => x.d < y.d ? -1 : 1);
  };
  out.weights = byDate(a.weights, b.weights);
  out.waist   = byDate(a.waist,   b.waist);

  const dates = new Set([...Object.keys(a.logs || {}), ...Object.keys(b.logs || {})]);
  for (const d of dates){
    const la = (a.logs || {})[d], lb = (b.logs || {})[d];
    if (d >= cutoff){
      // ?? {} guards a stored/incoming log entry that is explicitly null
      // (corrupt client write) rather than merely absent — without it this
      // throws and the account's sync is broken until the row is hand-edited.
      const pick = (newer.logs || {})[d] ?? (older.logs || {})[d] ?? {};
      out.logs[d] = { done: pick.done || [], mob: pick.mob || [], fuel: !!pick.fuel, note: pick.note || '' };
    } else {
      out.logs[d] = {
        // done holds stable exercise keys now (mob is still indices into a
        // fixed list). A numeric comparator returns NaN for strings and
        // leaves the order unspecified, so compare generically — this is
        // presentation order only; membership and count are what matter.
        done: [...new Set([...(la?.done || []), ...(lb?.done || [])])].sort(cmp),
        mob : [...new Set([...(la?.mob  || []), ...(lb?.mob  || [])])].sort(cmp),
        fuel: !!(la?.fuel || lb?.fuel),
        note: la?.note || lb?.note || ''
      };
    }
  }

  const ids = new Set([...Object.keys(a.lifts || {}), ...Object.keys(b.lifts || {})]);
  for (const id of ids){
    const m = new Map();
    ((a.lifts || {})[id] || []).forEach(e => m.set(e.d, e));
    ((b.lifts || {})[id] || []).forEach(e => m.set(e.d, e));
    out.lifts[id] = [...m.values()].sort((x, y) => x.d < y.d ? -1 : 1);
  }

  // What the pyramid actually was on a given Saturday — cap and vest load.
  // Additive by date: it is a record of a session that happened, so an older
  // device that still remembers a week this one never saw should keep it.
  const pyrDates = new Set([...Object.keys(a.pyramidLog || {}), ...Object.keys(b.pyramidLog || {})]);
  for (const d of pyrDates){
    out.pyramidLog[d] = (b.pyramidLog || {})[d] ?? (a.pyramidLog || {})[d];
  }

  // Recorded WHOOP readings, keyed by date. Purely additive across devices:
  // both read the same WHOOP account, so a disagreement on a given day just
  // means one of them fetched before the score settled. Prefer whichever
  // side actually has a value per field, so a partial early read can't blank
  // a complete later one. The recency rules above deliberately don't apply —
  // this is observed history, not something anyone edits.
  const whoopDates = new Set([...Object.keys(a.whoop || {}), ...Object.keys(b.whoop || {})]);
  for (const d of whoopDates){
    const wa = (a.whoop || {})[d] || {}, wb = (b.whoop || {})[d] || {};
    const pick = k => wb[k] ?? wa[k] ?? null;
    out.whoop[d] = {
      recovery: pick('recovery'), strain: pick('strain'),
      sleep: pick('sleep'), hrv: pick('hrv'), rhr: pick('rhr')
    };
  }
  return out;
}

/* ---------- storage ---------- */
async function readState(env, email){
  const row = await env.DB.prepare('SELECT json FROM state WHERE email = ?').bind(email).first();
  if (!row) return null;
  try { return JSON.parse(row.json); } catch { return null; }
}
async function writeState(env, email, state){
  await env.DB.prepare(
    `INSERT INTO state (email, json, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(email) DO UPDATE SET json = excluded.json, updated_at = excluded.updated_at`
  ).bind(email, JSON.stringify(state), Date.now()).run();
}
async function deleteState(env, email){
  await env.DB.prepare('DELETE FROM state WHERE email = ?').bind(email).run();
}

/* ---------- handlers ---------- */
export async function onRequestGet({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  const state = await readState(env, email);
  return json({ email, state, found: !!state });
}

export async function onRequestPut({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  const raw = await request.text();
  // .length counts UTF-16 code units, not bytes — undercounts anything
  // multi-byte and would let a payload past MAX_BODY that's actually larger.
  if (new TextEncoder().encode(raw).length > MAX_BODY) return json({ error: 'State too large.' }, 413);

  let incoming;
  try { incoming = JSON.parse(raw); }
  catch { return json({ error: 'Body is not valid JSON.' }, 400); }
  if (!incoming || typeof incoming !== 'object' || !('weights' in incoming))
    return json({ error: 'Body does not look like app state.' }, 400);

  const merged = mergeState(await readState(env, email), incoming);
  await writeState(env, email, merged);
  return json({ email, state: merged, merged: true });
}

export async function onRequestDelete({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  await deleteState(env, email);
  return json({ deleted: true });
}

export const onRequestOptions = () => new Response(null, {
  status: 204,
  headers: { allow: 'GET, PUT, DELETE, OPTIONS' }
});
