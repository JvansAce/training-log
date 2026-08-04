import * as state from '../functions/api/state.js';
import * as whoopAuthorize from '../functions/api/whoop/authorize.js';
import * as whoopCallback from '../functions/api/whoop/callback.js';
import * as whoopToday from '../functions/api/whoop/today.js';
import * as whoopDisconnect from '../functions/api/whoop/disconnect.js';

const routes = {
  'GET /api/state': state.onRequestGet,
  'PUT /api/state': state.onRequestPut,
  'OPTIONS /api/state': state.onRequestOptions,
  'GET /api/whoop/authorize': whoopAuthorize.onRequestGet,
  'GET /api/whoop/callback': whoopCallback.onRequestGet,
  'GET /api/whoop/today': whoopToday.onRequestGet,
  'POST /api/whoop/disconnect': whoopDisconnect.onRequestPost,
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const handler = routes[`${request.method} ${url.pathname}`];
    if (handler) return handler({ request, env, ctx });
    return env.ASSETS.fetch(request);
  }
};
