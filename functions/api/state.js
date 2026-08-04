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

const RECENT_DAYS = 2;          // within this window, latest write wins
const MAX_BODY = 2_000_000;     // 2 MB ceiling on a pushed state

/* ---------- merge ---------- */
const daysAgo = n => {
  const d = new Date(); d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
};

/* Additive by default so nothing is ever lost, but recent days take the
   latest write so that unticking something on the device in your hand
   actually sticks. */
export function mergeState(stored, incoming){
  const a = stored || {}, b = incoming || {};
  const newer = (b.updatedAt || 0) >= (a.updatedAt || 0) ? b : a;
  const older = newer === b ? a : b;
  const cutoff = daysAgo(RECENT_DAYS);

  const out = {
    updatedAt : Math.max(a.updatedAt || 0, b.updatedAt || 0),
    startDate : newer.startDate  ?? older.startDate  ?? null,
    pyramidCap: newer.pyramidCap ?? older.pyramidCap ?? 6,
    calAdjust : newer.calAdjust  ?? older.calAdjust  ?? 0,
    weights: [], logs: {}, lifts: {}
  };

  const wmap = new Map();
  (a.weights || []).forEach(w => wmap.set(w.d, w));
  (b.weights || []).forEach(w => wmap.set(w.d, w));   // same morning: newest push wins
  out.weights = [...wmap.values()].sort((x, y) => x.d < y.d ? -1 : 1);

  const dates = new Set([...Object.keys(a.logs || {}), ...Object.keys(b.logs || {})]);
  for (const d of dates){
    const la = (a.logs || {})[d], lb = (b.logs || {})[d];
    if (d >= cutoff){
      const pick = (newer.logs || {})[d] ?? (older.logs || {})[d];
      out.logs[d] = { done: pick.done || [], mob: pick.mob || [], fuel: !!pick.fuel };
    } else {
      out.logs[d] = {
        done: [...new Set([...(la?.done || []), ...(lb?.done || [])])].sort((p, q) => p - q),
        mob : [...new Set([...(la?.mob  || []), ...(lb?.mob  || [])])].sort((p, q) => p - q),
        fuel: !!(la?.fuel || lb?.fuel)
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
  if (raw.length > MAX_BODY) return json({ error: 'State too large.' }, 413);

  let incoming;
  try { incoming = JSON.parse(raw); }
  catch { return json({ error: 'Body is not valid JSON.' }, 400); }
  if (!incoming || typeof incoming !== 'object' || !('weights' in incoming))
    return json({ error: 'Body does not look like app state.' }, 400);

  const merged = mergeState(await readState(env, email), incoming);
  await writeState(env, email, merged);
  return json({ email, state: merged, merged: true });
}

export const onRequestOptions = () => new Response(null, {
  status: 204,
  headers: { allow: 'GET, PUT, OPTIONS' }
});
