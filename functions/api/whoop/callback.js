/* GET /api/whoop/callback
   Where WHOOP sends the browser back to after consent. Also reached by
   full page navigation, never by fetch, so errors here either redirect
   with a status the app can toast, or fall back to a small readable page
   for cases the app was never loaded (e.g. Access itself rejected it). */

import { htmlError } from '../../_shared.js';

const TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';
const STATE_MAX_AGE_MS = 10 * 60 * 1000;

export async function onRequestGet({ request, env }){
  const url = new URL(request.url);
  const code = url.searchParams.get('code');
  const state = url.searchParams.get('state');
  const deniedOrError = url.searchParams.get('error');

  const back = tag => new Response(null, {
    status: 302,
    headers: { location: `${url.origin}/?whoop=${tag}#/setup` }
  });

  if (deniedOrError) return back('denied');
  if (!code || !state) return back('error');
  if (!env.DB) return htmlError('No D1 binding named DB on this project.');

  const row = await env.DB.prepare(
    `SELECT email, created_at FROM whoop_oauth_state WHERE state = ?`
  ).bind(state).first();
  // Single-use regardless of outcome — a state value is never valid twice.
  await env.DB.prepare(`DELETE FROM whoop_oauth_state WHERE state = ?`).bind(state).run();

  if (!row || Date.now() - row.created_at > STATE_MAX_AGE_MS) return back('expired');
  if (!env.WHOOP_CLIENT_ID || !env.WHOOP_CLIENT_SECRET){
    return htmlError('WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET are not both set on this project.');
  }

  const redirectUri = new URL('/api/whoop/callback', request.url).toString();
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: redirectUri,
    client_id: env.WHOOP_CLIENT_ID,
    client_secret: env.WHOOP_CLIENT_SECRET
  });

  const tokRes = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!tokRes.ok) return back('tokenerror');

  const tok = await tokRes.json();
  // Refresh a minute before the stated expiry, not exactly at it, so a
  // slow request never straddles the boundary and gets rejected mid-flight.
  const expiresAt = Date.now() + (tok.expires_in || 3600) * 1000 - 60_000;

  await env.DB.prepare(
    `INSERT INTO whoop_tokens (email, access_token, refresh_token, expires_at, scope, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)
     ON CONFLICT(email) DO UPDATE SET
       access_token = excluded.access_token,
       refresh_token = excluded.refresh_token,
       expires_at = excluded.expires_at,
       scope = excluded.scope,
       updated_at = excluded.updated_at`
  ).bind(row.email, tok.access_token, tok.refresh_token, expiresAt, tok.scope || '', Date.now()).run();

  return back('connected');
}
