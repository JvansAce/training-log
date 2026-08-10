/* POST /api/whoop/exchange
   Called by the native iOS app, never by the web app or a browser
   navigation — that's why this doesn't import identify() or touch D1, unlike
   every other function in this folder. The web app has an account (a signed-
   in email, a row in D1) because it syncs a whole log through this same
   server. The iOS app has neither: its log lives in the user's own iCloud,
   and this endpoint's only job is the one thing that genuinely cannot happen
   on-device — trading a WHOOP authorization code for tokens without ever
   putting WHOOP_CLIENT_SECRET in the app binary, where anyone could extract
   it and impersonate this app to WHOOP.

   Being unauthenticated by design, this path — and /api/whoop/refresh next
   to it — MUST be carved out of whatever Cloudflare Access application
   fronts this hostname (Access → your application → Policies → add a Bypass
   policy for these two paths). Left un-carved, Access's login redirect
   intercepts the request before it ever reaches this function, and the
   symptom looks exactly like a WHOOP problem.

   The one thing this endpoint is missing that D1-backed identify() would
   give it is knowing WHO is asking. That's an acceptable trade here: the
   worst a stranger can do by calling this with someone else's own WHOOP
   authorization code is connect THEIR OWN WHOOP account through this app's
   registered client — spending this app's WHOOP developer-app rate limit,
   never anyone's data. Set WHOOP_APP_TOKEN (any string) on the Pages project
   and the same string in the app's WhoopConfig.appToken to require a shared
   header on top of that; leave both unset and the endpoint works with no
   extra setup, just that residual risk. */

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

  const { code, redirect_uri, code_verifier } = payload;
  if (!code || !redirect_uri || !code_verifier){
    return json({ error: 'code, redirect_uri and code_verifier are all required' }, 400);
  }

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri,
    code_verifier,
    client_id: env.WHOOP_CLIENT_ID,
    client_secret: env.WHOOP_CLIENT_SECRET
  });

  const tokRes = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body
  });
  if (!tokRes.ok){
    // WHOOP's own error text (invalid_grant, etc.) is more useful to
    // whoever is debugging a broken connect flow than a bare status code.
    const detail = await tokRes.text().catch(() => '');
    return json({ error: 'WHOOP rejected the exchange', detail }, 400);
  }

  const tok = await tokRes.json();
  return json({
    access_token: tok.access_token,
    refresh_token: tok.refresh_token,
    expires_in: tok.expires_in || 3600
  });
}

const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
});
