/* GET /api/whoop/authorize
   Reached by a full page navigation (the Setup page's "Connect WHOOP"
   button sets location.href here), not by fetch — so failures below
   return a small readable page rather than JSON. */

import { identify, htmlError } from '../../_shared.js';

const AUTH_URL = 'https://api.prod.whoop.com/oauth/oauth2/auth';
const SCOPES = 'offline read:recovery read:cycles read:sleep read:profile';

export async function onRequestGet({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return htmlError(e.message, e.status || 401); }

  if (!env.WHOOP_CLIENT_ID) return htmlError('WHOOP_CLIENT_ID is not set on this project.');
  if (!env.DB) return htmlError('No D1 binding named DB on this project.');

  // Proves the /callback request that comes back really followed from an
  // authorize call we issued for this email, not a forged or replayed one.
  const state = crypto.randomUUID();
  await env.DB.prepare(
    `INSERT INTO whoop_oauth_state (state, email, created_at) VALUES (?, ?, ?)`
  ).bind(state, email, Date.now()).run();

  const redirectUri = new URL('/api/whoop/callback', request.url).toString();
  const params = new URLSearchParams({
    client_id: env.WHOOP_CLIENT_ID,
    redirect_uri: redirectUri,
    response_type: 'code',
    scope: SCOPES,
    state
  });

  return Response.redirect(`${AUTH_URL}?${params.toString()}`, 302);
}
