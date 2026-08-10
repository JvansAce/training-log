/* POST /api/whoop/refresh
   The native app's counterpart to exchange.js — same reasoning, same
   Access-bypass requirement, same residual risk, see the comment there. This
   one exists because the same secret that traded the original code for
   tokens is also the one WHOOP demands on every refresh. */

const TOKEN_URL = 'https://api.prod.whoop.com/oauth/oauth2/token';

export async function onRequestPost({ request, env }){
  if (!env.WHOOP_CLIENT_ID || !env.WHOOP_CLIENT_SECRET){
    return json({ error: 'WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET are not both set on this project.' }, 503);
  }
  if (env.WHOOP_APP_TOKEN && request.headers.get('x-app-token') !== env.WHOOP_APP_TOKEN){
    return json({ error: 'missing or wrong app token' }, 401);
  }

  let payload;
  try { payload = await request.json(); }
  catch (e){ return json({ error: 'expected a JSON body' }, 400); }

  const { refresh_token } = payload;
  if (!refresh_token) return json({ error: 'refresh_token is required' }, 400);

  const body = new URLSearchParams({
    grant_type: 'refresh_token',
    refresh_token,
    client_id: env.WHOOP_CLIENT_ID,
    client_secret: env.WHOOP_CLIENT_SECRET
  });

  const tokRes = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!tokRes.ok){
    // A dead refresh token — WHOOP rotates it on every use, so this is what
    // a stale or already-used one looks like. The app's answer to this is
    // to drop the connection and ask the person to reconnect; it is not
    // retryable.
    return json({ error: 'reconnect' }, 400);
  }

  const tok = await tokRes.json();
  // WHOOP is expected to always send a fresh refresh_token; if a response
  // ever omits one, the caller keeps using the one it already has rather
  // than being handed nothing to fall back on.
  return json({
    access_token: tok.access_token,
    refresh_token: tok.refresh_token || refresh_token,
    expires_in: tok.expires_in || 3600
  });
}

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
});
