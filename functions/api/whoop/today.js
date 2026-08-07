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
  // WHOOP is expected to always send a fresh refresh_token, but if a
  // response ever omits one, falling back to the still-valid one we had
  // beats writing NULL into a NOT NULL column and breaking the account.
  const refreshToken = tok.refresh_token || row.refresh_token;
  await env.DB.prepare(
    `UPDATE whoop_tokens SET access_token = ?, refresh_token = ?, expires_at = ?, updated_at = ? WHERE email = ?`
  ).bind(tok.access_token, refreshToken, expiresAt, Date.now(), email).run();

  return { token: tok.access_token };
}

async function whoopGet(path, token){
  const res = await fetch(`${API_BASE}${path}`, { headers: { authorization: `Bearer ${token}` } });
  if (!res.ok) return { ok: false, status: res.status };
  return { ok: true, data: await res.json() };
}

export async function onRequestGet({ request, env }){
  const url = new URL(request.url);
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  const { token, reason } = await getValidToken(env, email);
  if (!token) return json({ connected: false, reason: reason || 'not_connected' });

  // Workouts get a larger limit than the rest: several can happen in a day,
  // and unlike recovery/cycle/sleep we want all of today's, not just the
  // most recent one.
  const [recRes, cycRes, sleepRes, workRes] = await Promise.all([
    whoopGet('/recovery?limit=1', token),
    whoopGet('/cycle?limit=1', token),
    whoopGet('/activity/sleep?limit=1', token),
    whoopGet('/activity/workout?limit=10', token)
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

  // ?limit=1 returns the single most recent record ever, with no date
  // filter — before today's recovery has scored, that's yesterday's, and
  // without this check it gets displayed as if it were today's, including
  // driving the "recovery is red, take it easy" advice off a stale number.
  //
  // "Today" has to be the CLIENT's calendar day. This Worker runs in UTC
  // while the app keys everything on local dates, so for anyone east of
  // Greenwich the small hours of the morning are still yesterday in UTC —
  // a real reading would be filtered out as stale and the app would show
  // nothing. The client sends its own date; UTC is only the fallback for a
  // caller that doesn't.
  const asked = url.searchParams.get('d');
  const today = /^\d{4}-\d{2}-\d{2}$/.test(asked || '') ? asked : new Date().toISOString().slice(0, 10);
  const isToday = ts => !!ts && new Date(ts).toISOString().slice(0, 10) === today;
  const recoveryToday = recovery && isToday(recovery.created_at) ? recovery : null;
  const cycleToday    = cycle    && isToday(cycle.start    || cycle.created_at) ? cycle    : null;
  const sleepToday    = sleep    && isToday(sleep.start    || sleep.created_at) ? sleep    : null;

  return json({
    connected: true,
    as_of: new Date().toISOString(),
    recovery: recoveryToday ? {
      state: recoveryToday.score_state,
      score: recoveryToday.score?.recovery_score ?? null,
      hrv_ms: recoveryToday.score?.hrv_rmssd_milli ?? null,
      rhr: recoveryToday.score?.resting_heart_rate ?? null
    } : null,
    strain: cycleToday ? {
      state: cycleToday.score_state,
      value: cycleToday.score?.strain ?? null
    } : null,
    sleep: sleepToday ? {
      state: sleepToday.score_state,
      performance_pct: sleepToday.score?.sleep_performance_percentage ?? null
    } : null,
    // Empty array rather than null when the call simply found nothing, so
    // the client can tell "no workouts today" apart from "this WHOOP
    // connection predates the read:workout scope and can't see them".
    workouts: workRes.ok
      ? (workRes.data.records || [])
          .filter(wk => isToday(wk.start || wk.created_at))
          .map(wk => ({
            id: wk.id ?? null,
            sport: wk.sport_name ?? null,
            start: wk.start ?? null,
            minutes: wk.start && wk.end
              ? Math.round((new Date(wk.end) - new Date(wk.start)) / 60000) : null,
            strain: wk.score?.strain ?? null,
            kilojoule: wk.score?.kilojoule ?? null
          }))
      : null
  });
}
