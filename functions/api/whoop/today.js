/* GET /api/whoop/today
   Called by the client via fetch, so this always returns JSON — including
   on failure, so the frontend can show something specific rather than a
   generic network error. */

import { identify, json } from '../../_shared.js';

const TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';
const API_BASE = 'https://api.prod.whoop.com/developer/v2';

async function getValidToken(env, email){
  const row = await env.DB.prepare(
    `SELECT access_token, refresh_token, expires_at FROM whoop_tokens WHERE email = ?`
  ).bind(email).first();
  if (!row) return { token: null, reason: 'not_connected' };
  if (Date.now() < row.expires_at) return { token: row.access_token };

  // Expired — refresh. WHOOP rotates the refresh token on every use: the
  // response's refresh_token replaces what we had, the old one is dead.
  // For one person on one or two devices, a race between two simultaneous
  // refreshes is unlikely; if it ever happens, the loser just gets
  // 'reconnect' below and reconnecting fixes it in ten seconds.
  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token: row.refresh_token,
    client_id: env.WHOOP_CLIENT_ID,
    client_secret: env.WHOOP_CLIENT_SECRET
  });
  const res = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!res.ok) return { token: null, reason: 'reconnect' };

  const tok = await res.json();
  const expiresAt = Date.now() + (tok.expires_in || 3600) * 1000 - 60_000;
  await env.DB.prepare(
    `UPDATE whoop_tokens SET access_token = ?, refresh_token = ?, expires_at = ?, updated_at = ? WHERE email = ?`
  ).bind(tok.access_token, tok.refresh_token, expiresAt, Date.now(), email).run();

  return { token: tok.access_token };
}

async function whoopGet(path, token){
  const res = await fetch(`${API_BASE}${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) return { ok: false, status: res.status };
  return { ok: true, data: await res.json() };
}

export async function onRequestGet({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  const { token, reason } = await getValidToken(env, email);
  if (!token) return json({ connected: false, reason: reason || 'not_connected' });

  const [recRes, cycRes, sleepRes] = await Promise.all([
    whoopGet('/recovery?limit=1', token),
    whoopGet('/cycle?limit=1', token),
    whoopGet('/activity/sleep?limit=1', token)
  ]);

  if (!recRes.ok && recRes.status === 401){
    // WHOOP rejected the token outright — most likely the person revoked
    // access from WHOOP's own app settings rather than from here.
    await env.DB.prepare(`DELETE FROM whoop_tokens WHERE email = ?`).bind(email).run();
    return json({ connected: false, reason: 'revoked' });
  }

  const recovery = recRes.ok ? recRes.data.records?.[0] : null;
  const cycle    = cycRes.ok ? cycRes.data.records?.[0]  : null;
  const sleep    = sleepRes.ok ? sleepRes.data.records?.[0] : null;

  return json({
    connected: true,
    as_of: new Date().toISOString(),
    recovery: recovery ? {
      state: recovery.score_state,
      score: recovery.score?.recovery_score ?? null,
      hrv_ms: recovery.score?.hrv_rmssd_milli ?? null,
      rhr: recovery.score?.resting_heart_rate ?? null
    } : null,
    strain: cycle ? {
      state: cycle.score_state,
      value: cycle.score?.strain ?? null
    } : null,
    sleep: sleep ? {
      state: sleep.score_state,
      performance_pct: sleep.score?.sleep_performance_percentage ?? null
    } : null
  });
}
