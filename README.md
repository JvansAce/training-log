# Brand New Body

A single-page training log for the lean-bulk plan: Tuesday/Wednesday/Friday/Saturday lifting, Monday tennis, Thursday easy cardio, Sunday rest. Four pages — Today, Week, Progress, Setup. No build step, no dependencies, no backend.


## Files


| File | Purpose |
| --- | --- |
| `index.html` | Shell: masthead, view container, tab bar |
| `app.css` | All styling |
| `app.js` | Plan data, storage, hash router, the four views |
| `manifest.webmanifest` | Home-screen install metadata |
| `sw.js` | Service worker — caches the shell so it works offline |
| `sync.js` | Client sync layer — talks to `/api/state` |
| `whoop.js` | Client WHOOP layer — talks to `/api/whoop/*` |
| `functions/_shared.js` | Shared Access identity check used by every function below |
| `functions/api/state.js` | Pages Function: authenticated read/write with server-side merge |
| `functions/api/whoop/authorize.js` | Starts the WHOOP OAuth flow |
| `functions/api/whoop/callback.js` | Handles WHOOP's redirect back, exchanges the code for tokens |
| `functions/api/whoop/today.js` | Returns today's recovery/strain/sleep, refreshing the token if needed |
| `functions/api/whoop/disconnect.js` | Revokes and deletes the stored WHOOP tokens |
| `schema.sql` | D1 tables — training state, WHOOP tokens, OAuth state |
| `icon.svg`, `icon-192.png`, `icon-512.png` | App icons |
| `DEPLOY.md` | Step-by-step deployment walkthrough — start there |

## Where the data lives

Two places, on purpose.

**Locally:** `localStorage`, key `bnb.v1`. This is the source of truth while you're using the app, which is why it works with no signal in a basement gym.

**On the server:** one row per signed-in email in a D1 database, written through `/api/state`. Every device you sign into reads and writes that same row, so the phone in the garage and the laptop upstairs converge.

Pushes are debounced by about 2.5 seconds, and also fire when you come back online or return to the tab. The footer shows the current state: `SYNCED 18:04`, `OFFLINE · CHANGES PENDING`, `LOCAL ONLY`, or `SIGN IN AGAIN TO SYNC`.

Setup → **Export file** still writes a JSON backup. Worth doing occasionally regardless — sync protects you from losing a device, not from your own bad afternoon with the delete button.

### How conflicts resolve

The server merges rather than overwrites, because a training log is mostly additive:

- **Weigh-ins and logged sets** merge by date. Two devices with different history end up with the union of both.
- **Anything older than two days** is only ever added to. A tick recorded on one device can't be erased by a stale push from another.
- **Today and yesterday** take the most recent write, so unticking something on the device in your hand actually sticks.
- **Settings** (start date, pyramid cap, calorie adjustment) follow whichever record was touched most recently.

The one honest limitation: because old days are additive, unticking an exercise from last week on one device won't propagate to the others. That trade buys you never silently losing a session, which is the failure that would actually matter.

## Hosting: Cloudflare Pages + Access

**New to Cloudflare? Follow `DEPLOY.md` instead — it's the same setup written out stage by stage with checks after each one.** What follows is the condensed version.

Two stages. Stage one puts the site online; stage two puts a login in front of it. Both are free.

### 1. Deploy

dash.cloudflare.com → **Workers & Pages** → Create → Pages → **Upload assets**. Drag this folder in, name the project, deploy. You get `https://PROJECT.pages.dev`.

### 2. Optionally point a subdomain at it

Not required — Access can protect the free `yourproject.pages.dev` URL, so a domain is a nicety rather than a dependency. If you do want one: Pages project → Custom domains → Set up a domain → `training.yourdomain.de`. If the domain's nameservers are already at Cloudflare, the DNS record is created for you. Note that a custom domain needs its own Access application even if `pages.dev` already has one.

### 3. Put Access in front

1. Zero Trust dashboard → Settings → Authentication → confirm **One-time PIN** is in the login methods list. Add it if it isn't. No further configuration.
2. Zero Trust → **Access controls → Applications** → **Create new application** → **Self-hosted**.
3. Add the public hostname — either `yourproject.pages.dev` or your custom domain.
4. Under Access policies, create a policy: Action **Allow**, rule **Emails** → your address. Add a second address for anyone else who should get in.
5. Save.

Now every request to that hostname hits a Cloudflare login page first. You enter your email, Cloudflare mails a one-time code, and the session lasts as long as the app's session duration (24h by default — worth raising to a week or a month so you're not doing this before every workout).

Free plan covers 50 users.

### What the app does with it

On load it reads `/cdn-cgi/access/get-identity`, and if Cloudflare returns an identity, Setup shows the signed-in email and a **Sign out** button (which hits `/cdn-cgi/access/logout`). Off Access — running locally, or on a plain static host — that request just fails and the app carries on, with Setup noting that this copy is open to anyone with the URL.

The service worker deliberately skips anything under `/cdn-cgi/`, so login state is never served from cache.

### Other hosts

Plain static hosting works anywhere — GitHub Pages, Netlify, or nginx/Caddy on your own box:

```
# Caddyfile
training.example.de {
    root * /srv/training
    file_server
}
```

Caddy handles TLS itself, which matters because the service worker and the install prompt both require HTTPS. Note that Access only fronts hostnames proxied through Cloudflare, so self-hosting means either a Cloudflare Tunnel or no Access.

### 4. Create the database

Install Wrangler if you haven't (`npm i -g wrangler`, then `wrangler login`), then:

```bash
wrangler d1 create training-log
wrangler d1 execute training-log --remote --file=./schema.sql
```

The first command prints a database ID; you won't need it if you bind through the dashboard.

### 5. Bind it and configure the API

Pages project → **Settings → Functions**:

- **D1 database bindings** → variable name `DB` → database `training-log`
- **Environment variables** (Production):
  - `ACCESS_TEAM_DOMAIN` = `yourteam.cloudflareaccess.com`
  - `ACCESS_AUD` = the **Application Audience (AUD) tag**, copied from the Access application's overview page

Redeploy after adding bindings — Pages only picks them up on a new deployment.

Then open the site, go to Setup, and the Sync panel should read *Your log is on the server*. If it says *not configured*, one of the two variables is missing or the D1 binding isn't named `DB`.

### Why the API verifies a token instead of trusting a header

Access injects `Cf-Access-Authenticated-User-Email` into every request, and it's tempting to read that and be done. But if a request ever reaches the origin without passing through Access — a DNS misconfiguration, a `.pages.dev` URL that isn't covered by the application — that header is just a string the caller controls, and anyone could read or write your record by setting it.

So `functions/_shared.js` verifies the `Cf-Access-Jwt-Assertion` JWT instead: RS256 signature checked against your team's published keys, plus issuer, audience and expiry. The keys are cached in the isolate for an hour. If `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` aren't set, every endpoint refuses to serve rather than falling back to the header — failing closed instead of open. Every function under `functions/api/` imports this one check rather than reimplementing it.

### Local development

```bash
npx wrangler pages dev . --d1 DB=training-log --binding DEV_EMAIL=you@example.de
```

`DEV_EMAIL` bypasses token verification and acts as that user. **Never set it in production** — it's an unauthenticated back door by design.

## WHOOP

Optional. Connects your WHOOP account so the Today page shows live recovery, strain and sleep, and flags days recovery is low.

**Full setup steps are in `DEPLOY.md` (Stage 10)** — registering a developer app at developer.whoop.com, the two extra environment variables, and re-running `schema.sql` (it's additive, safe to run again). The short version:

1. Create an app at developer-dashboard.whoop.com, redirect URI `https://yourdomain/api/whoop/callback`.
2. Add `WHOOP_CLIENT_ID` (plaintext) and `WHOOP_CLIENT_SECRET` (**as an encrypted secret**, not plaintext — unlike the Access variables, this one is a real credential) to the Pages project.
3. Redeploy, then Setup → **Connect WHOOP**.

Tokens live in the `whoop_tokens` D1 table, keyed by the same email Access already verified — never sent to or stored in the browser. WHOOP rotates the refresh token on every use; `functions/api/whoop/today.js` always persists the new one it's handed back, never the one it started with.

## Install on the phone

Open the URL, then:
- **iOS Safari:** Share → Add to Home Screen
- **Android Chrome:** menu → Install app

It opens fullscreen without browser chrome and keeps working without signal.

## Editing the plan

Everything is data at the top of `app.js`:

- `SCHEDULE` — one entry per weekday (`0` = Sunday). Add an `id` to any exercise to give it inline `kg × reps` logging; leave it off for warm-ups.
- `MOBILITY`, `MEALS`, `ADDINS` — plain lists.
- `fuel()` — calorie and macro maths. Rest days are Thursday and Sunday.

Adding a fifth page takes two lines: write `VIEWS.myPage = () => \`...\`` and add `<a href="#/myPage" data-tab="myPage">Label</a>` to the tab bar. If it needs event handlers, add a `wireMyPage()` call in `render()`.

**After any edit, bump `CACHE` in `sw.js`** (`bnb-v1` → `bnb-v2`) or the service worker will keep serving the old version.
