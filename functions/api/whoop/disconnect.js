/* POST /api/whoop/disconnect */

import { identify, json } from '../../_shared.js';

export async function onRequestPost({ request, env }){
  let email;
  try { email = await identify(request, env); }
  catch (e){ return json({ error: e.message }, e.status || 401); }
  if (!env.DB) return json({ error: 'No D1 binding named DB on this project.' }, 503);

  const row = await env.DB.prepare(
    `SELECT access_token FROM whoop_tokens WHERE email = ?`
  ).bind(email).first();

  if (row){
    // Best effort — so this app also disappears from WHOOP's own connected-
    // apps list, not just from our side. A failure here shouldn't block
    // disconnecting locally, which is the part the person actually asked for.
    try{
      await fetch('https://api.prod.whoop.com/developer/v2/user/access', {
        method: 'DELETE',
        headers: { authorization: `Bearer ${row.access_token}` }
      });
    }catch(e){ /* ignore */ }
  }

  await env.DB.prepare(`DELETE FROM whoop_tokens WHERE email = ?`).bind(email).run();
  return json({ disconnected: true });
}
