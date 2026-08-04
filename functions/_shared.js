/* ============================================================
   Shared by every Pages Function in this project. Kept in one place
   because "who is making this request" is the one thing every
   endpoint below needs to get right, and it should only have to be
   right once.

   Files starting with an underscore are excluded from Cloudflare's
   route matching, so this file is importable but never itself a URL.
   ============================================================ */

/* ---------- base64url ---------- */
const b64uToBytes = s => {
  const b = atob(s.replace(/-/g,'+').replace(/_/g,'/').padEnd(Math.ceil(s.length/4)*4,'='));
  return Uint8Array.from(b, c => c.charCodeAt(0));
};
const b64uToJson = s => JSON.parse(new TextDecoder().decode(b64uToBytes(s)));

/* ---------- JWKS, cached in the isolate ---------- */
let jwksCache = { at: 0, keys: null, domain: '' };
async function getKeys(teamDomain){
  const fresh = Date.now() - jwksCache.at < 3600_000;
  if (fresh && jwksCache.keys && jwksCache.domain === teamDomain) return jwksCache.keys;
  const res = await fetch(`https://${teamDomain}/cdn-cgi/access/certs`);
  if (!res.ok) throw new Error('cannot reach Access certs');
  const { keys } = await res.json();
  jwksCache = { at: Date.now(), keys, domain: teamDomain };
  return keys;
}

async function verifyAccessJwt(token, teamDomain, aud){
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('malformed token');
  const [h, p, sig] = parts;
  const header = b64uToJson(h);
  if (header.alg !== 'RS256') throw new Error('unexpected algorithm');

  const jwk = (await getKeys(teamDomain)).find(k => k.kid === header.kid);
  if (!jwk) throw new Error('signing key not found');

  const key = await crypto.subtle.importKey(
    'jwk', { kty: jwk.kty, n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['verify']);

  const ok = await crypto.subtle.verify('RSASSA-PKCS1-v1_5', key,
    b64uToBytes(sig), new TextEncoder().encode(`${h}.${p}`));
  if (!ok) throw new Error('bad signature');

  const claims = b64uToJson(p);
  const now = Math.floor(Date.now() / 1000);
  if (claims.exp && claims.exp < now) throw new Error('token expired');
  if (claims.nbf && claims.nbf > now + 60) throw new Error('token not yet valid');
  if (claims.iss !== `https://${teamDomain}`) throw new Error('wrong issuer');
  const auds = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!auds.includes(aud)) throw new Error('wrong audience');
  if (!claims.email) throw new Error('token carries no email');
  return claims.email.toLowerCase();
}

/* Returns a lowercase email on success. Throws an Error with a .status
   on failure. DEV_EMAIL is a local-development escape hatch only —
   never set it in production, it skips verification entirely. */
export async function identify(request, env){
  if (env.DEV_EMAIL) return env.DEV_EMAIL.toLowerCase();
  if (!env.ACCESS_TEAM_DOMAIN || !env.ACCESS_AUD){
    throw Object.assign(new Error(
      'Access is not configured. Set ACCESS_TEAM_DOMAIN and ACCESS_AUD on the Pages project.'
    ), { status: 503 });
  }
  const token = request.headers.get('Cf-Access-Jwt-Assertion');
  if (!token) throw Object.assign(new Error('No Access token on this request.'), { status: 401 });
  try{
    return await verifyAccessJwt(token, env.ACCESS_TEAM_DOMAIN, env.ACCESS_AUD);
  }catch(e){
    throw Object.assign(new Error(`Access token rejected: ${e.message}`), { status: 401 });
  }
}

export const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store' }
});

/* For endpoints reached by a full page navigation (OAuth redirects) rather
   than fetch — a JSON error body there would just render as raw text with
   nothing to click, so these get a minimal readable page instead. */
export const htmlError = (msg, status = 503) => new Response(
  `<!doctype html><meta charset="utf-8"><body style="font-family:system-ui;background:#141824;color:#EDE7DB;padding:2rem;line-height:1.5;max-width:32rem;margin:0 auto">
  <p>${msg}</p><p><a href="/#/setup" style="color:#4C7BE8">Back to Setup</a></p></body>`,
  { status, headers: { 'content-type': 'text/html' } }
);
