# Deploying the training log — iPhone only

No Mac, no Terminal, no command line anywhere in this. Everything happens in Safari and the Files app. Every step says exactly what to tap and what you should see afterward — if something looks different on your screen, stop and check rather than pushing on, since that's usually the fastest way to find where it went sideways.

**Time:** 45–60 minutes in one sitting. **Cost:** €0.

**Use Safari, not the GitHub app**, for anything involving creating files — the GitHub app doesn't support it, but github.com works fine as a plain website in mobile Safari.

---

## Before you start

### Create a Cloudflare account

1. Open Safari, go to **dash.cloudflare.com**.
2. Tap **Sign up**.
3. Enter your email and a password, verify the email if asked.
4. You land on an empty dashboard. No payment details needed anywhere in this walkthrough.

---

## Stage 1 — Get the project files onto your iPhone

1. In Safari, download the project zip from wherever you got it (the same download link from this conversation works fine on the phone).
2. Open the **Files** app, find the downloaded `.zip` in **Downloads**.
3. Tap it once — iOS unzips it automatically into a folder of the same name, right there in Files.
4. Open that folder and confirm you see `index.html`, `app.css`, `app.js`, `sync.js`, `whoop.js`, `sw.js`, `manifest.webmanifest`, `schema.sql`, a `functions` folder, and the icon files.

---

## Stage 2 — Create a GitHub account and a repository

1. In Safari, go to **github.com**, tap **Sign up** if you don't already have an account. Free.
2. Once signed in, tap the **+** icon (top right) → **New repository**.
3. Name it something simple, e.g. `training-log`.
4. Leave it **Public** — a private repo needs a paid plan to deploy from with Cloudflare Pages' free tier. Public here just means someone would need your exact repo name to find the source code, not your training data, which lives in the database, not the repo.
5. Tick **Add a README file** so the repo isn't empty. Tap **Create repository**.

---

## Stage 3 — Add the text files by pasting them in

For each file below, you'll create it directly on GitHub and paste its contents. In the repo, tap **Add file → Create new file**.

Do this once for each of:

- `index.html`
- `app.css`
- `app.js`
- `sync.js`
- `whoop.js`
- `sw.js`
- `manifest.webmanifest`
- `schema.sql`
- `icon.svg`
- `functions/_shared.js` — **type the full path including the slash** in the filename box. GitHub creates the `functions` folder automatically.
- `functions/api/state.js`
- `functions/api/whoop/authorize.js`
- `functions/api/whoop/callback.js`
- `functions/api/whoop/today.js`
- `functions/api/whoop/disconnect.js`

For each one:

1. Type the filename (or full path, for the ones with slashes) into the **Name your file...** box.
2. Go to the **Files** app, open that same file (tapping a text file previews it), tap and hold to **Select All**, then **Copy**.
3. Switch back to Safari, tap into the big empty text box, and **Paste**.
4. Scroll down, tap **Commit changes...**, then **Commit changes** again to confirm.

Fifteen files, one at a time, each under a minute. The five `whoop/` and `_shared.js` files only matter if you plan to do Stage 14 later — skip them for now if you're not sure yet, you can always add them the same way afterward.

---

## Stage 4 — Upload the two icon images

PNGs can't be pasted as text, so these use a different button.

1. In the repo, tap **Add file → Upload files**.
2. Tap **choose your files** — navigate to your unzipped folder in Files, select both `icon-192.png` and `icon-512.png` (tap **Select** in the top right of Files to enable picking more than one at once).
3. Scroll down, **Commit changes**.

---

## Stage 5 — Check everything's there

Go to the repo's main page. You should see all the files listed, with the `functions` folder showing a little folder icon. Tap into `functions → api` and confirm `state.js` and a `whoop` folder are there, then into `whoop` and confirm its four files. If something's missing, repeat Stage 3 or 4 for just that file.

---

## Stage 6 — Connect Cloudflare Pages to the repository

1. In Safari, go to **dash.cloudflare.com**, sign in.
2. **Workers & Pages** in the sidebar → **Create** → **Pages** tab → **Connect to Git**.
3. Authorize Cloudflare to access your GitHub account when prompted — a standard GitHub permission screen, tap **Authorize**.
4. Select your `training-log` repository from the list.
5. On the build settings screen:
   - **Framework preset:** None
   - **Build command:** leave empty
   - **Build output directory:** `/`
6. Tap **Save and Deploy**.

Cloudflare builds and deploys the site — since there's no actual build step, this takes well under a minute. You land on a page with your live URL, something like `https://training-log.pages.dev`. **This is your app's permanent address.** Bookmark it.

**Check:** open that URL. You should see the dark app load, with **"BRAND NEW BODY"** as the big heading and today's date underneath. Tap **Setup** — it should say something like *"this copy is not behind Cloudflare Access"* and small text at the bottom reads `LOCAL ONLY` or `SYNC NOT CONFIGURED`. **Both are correct right now** — login and the database aren't wired up yet.

**If the page is blank:** a build cutting off mid-upload is the usual cause — go to **Deployments → Retry deployment** and try again.

**From now on, any time you edit a file on GitHub and commit the change, Cloudflare automatically redeploys within a minute or two.** No separate push step to remember.

---

## Stage 7 — Create the database

1. In the Cloudflare dashboard, find **Workers & Pages** in the sidebar, then look for **D1 SQL Database** as its own entry — a sibling to Workers & Pages, not nested under your project.
2. Tap **Create Database**.
3. Name it `training-log`.
4. Under **Location hint**, choose **Western Europe (weur)**. **This can't be changed later without recreating the database**, so don't skip it.
5. Tap **Create**.

---

## Stage 8 — Run the schema

1. Open the database you just created, find the **Console** tab.
2. Open `schema.sql` — either back in Files, or by viewing the file you already pasted into GitHub — and copy its full contents.
3. Paste it into the Console's query box, tap **Run**.
4. You should see a success message.

**Check:** in the same Console, run:
```
SELECT name FROM sqlite_master WHERE type='table'
```
You should see `state`, `whoop_tokens`, and `whoop_oauth_state` — all three exist from the start even if you're not using WHOOP yet.

---

## Stage 9 — Set up your Cloudflare team (one-time, for login)

This is a one-time setup for your whole Cloudflare account, not just this project.

1. In the Cloudflare dashboard, find **Zero Trust** in the sidebar (Cloudflare has renamed this a few times — if you don't see it directly, look for **Access** or **Zero Trust & Access**).
2. First time in, it asks you to **choose a team name**. This becomes part of a URL: `yourteamname.cloudflareaccess.com`. Pick something short, lowercase, no spaces — e.g. your first name plus a word, like `jonastraining`.
3. **Write this team name down somewhere** — you'll type it exactly, including `.cloudflareaccess.com`, into an environment variable in Stage 11.
4. Confirm — nothing else to configure here.

### Turn on email login codes

1. Still in Zero Trust, **Settings** → **Authentication** → **Login methods**.
2. Check whether **One-time PIN** is already listed.
   - **There:** nothing more to do.
   - **Not there:** tap **Add new**, select **One-time PIN**, save.

---

## Stage 10 — Create the Access application (the actual login gate)

1. Still in Zero Trust, **Access controls** (older dashboards just call this **Access**) → **Applications**.
2. Tap **Create new application** (sometimes **+ Add an application**).
3. Choose **Self-hosted** — usually the first option.

### Fill in the details

1. **Application name** — anything, e.g. `Training log`.
2. **Session duration** — change from the default **24 hours** to **1 month**. Leave it at 24 hours and you'll be entering an email code before almost every workout.
3. Scroll to **Public hostname**:
   - **Subdomain** — your project name, e.g. `training-log`.
   - **Domain** — `pages.dev` may already be in the dropdown; select it. If not, use **"Switch to custom input"** and type the full address: `training-log.pages.dev`.
   - **Path** — leave empty, so the whole site is protected.
4. Continue to policies.

### Create the policy

1. **Policy name** — `Me` or similar.
2. **Action** — **Allow**.
3. Under **Rules → Include**, set **Selector** to **Emails**, type your email address.
4. Want someone else in too (partner, coach)? Add another **Emails** rule with their address — rules in one policy combine with OR.
5. **Save policy**, then finish creating the application.

### Copy the AUD tag

You need this in Stage 11. On the application's **Overview** page, find **Application Audience (AUD) Tag** — a long string of letters and numbers. Copy it, paste it somewhere temporary (Notes app is fine) until Stage 11.

### Also protect the preview URLs

Cloudflare Pages generates random preview addresses on every redeploy (like `a1b2c3.training-log.pages.dev`), which stay public by default even once your main URL is locked down.

1. **Workers & Pages** (the regular dashboard, not Zero Trust) → your `training-log` project → **Settings → General**.
2. Find **Access policy**, tap **Enable**.

This creates a second Access application automatically for the preview addresses — nothing else to configure.

### Check the login works

1. Open a **private browsing tab** in Safari (tap the tabs icon, then **Private**).
2. Go to your app's URL.
3. You should land on a Cloudflare-branded page asking for your email — **not** the training app.
4. Enter your email, tap **Send me a code**, check email for a 6-digit code, enter it.
5. **Now** you land on the app.

**If you reach the app directly with no login screen at all:** the hostname on the Access application doesn't exactly match your real URL — recheck the subdomain/domain fields character by character.

---

## Stage 11 — Bind the database and finish configuring

1. **Workers & Pages** → your project → **Settings**.
2. Find **Functions** or **Bindings** (the label shifts between dashboard versions — look for anything mentioning "D1" or "Bindings").
3. **D1 database bindings** → **Add binding**.
4. **Variable name** — exactly `DB` (capital letters).
5. **D1 database** — select **training-log**.
6. **Save**.

### Add the two environment variables

1. Still in **Settings**, find **Environment variables** (sometimes under **Variables and Secrets**).
2. Make sure you're in the **Production** environment.
3. **Add variable**, twice:

   | Variable name | Value |
   | --- | --- |
   | `ACCESS_TEAM_DOMAIN` | your team name from Stage 9, plus `.cloudflareaccess.com` — e.g. `jonastraining.cloudflareaccess.com` |
   | `ACCESS_AUD` | the AUD tag from Stage 10 |

   Both as **plain text**, not encrypted — neither is a real secret, just configuration. **`ACCESS_TEAM_DOMAIN` has no `https://` and no trailing slash** — the bare hostname only.

4. **Save**.

### Redeploy

Cloudflare only applies new bindings and variables to deployments made *after* you added them. Two ways to trigger a fresh one:

- Edit any file on github.com — even a trivial change like an extra blank line — and commit. That alone redeploys.
- Or: Cloudflare dashboard → your project → **Deployments** → latest one → **⋯** → **Retry deployment**.

### Check it worked

1. Open your app URL, sign in if asked, go to **Setup**.
2. You should see:
   - An **Account** panel with your email and a **Sign out** button.
   - A **Sync** panel saying *"Your log is on the server."*
   - Small text at the bottom reading `SYNCED` with a time.

**Still says "not configured"?** One of the two variable names is misspelled, or you forgot to redeploy — recheck `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` character by character.

**Says `LOCAL ONLY`?** The `functions` folder didn't make it into the repo — go back to Stage 5's check.

---

## Stage 12 — Prove it actually syncs

Worth doing once on purpose so you trust it later.

1. On your phone, in the app, **Today** → **Body weight**, log a number.
2. Open the same URL on a second device (or a private Safari tab, signed in with the same email) — the number should already be there.
3. Tick off two exercises there.
4. Back on the first device, reload — the ticks should show up too.

**Number missing?** Check you signed in with the exact same email on both. Two different addresses make two separate records — correct behaviour, just not what you meant to do.

---

## Stage 13 — Install it on your Home Screen

1. Open the app's URL in Safari.
2. Tap the **Share** icon (square with an arrow pointing up).
3. Scroll down, tap **Add to Home Screen**.
4. Tap **Add**.

It now opens full-screen with no address bar, and the app shell is cached, so it opens even with no signal in the gym. Anything logged offline pushes to the server once you're back on Wi-Fi or data — the status text at the bottom of Setup shows the current state.

---

## Stage 14 (optional) — Connect WHOOP

Adds live recovery, strain and sleep to the Today page, plus a warning when recovery is low. Skip this entirely and everything above still works exactly as described.

### A. Register a WHOOP developer app

1. Go to **developer-dashboard.whoop.com**, sign in with your regular WHOOP account.
2. Create a new app — name it anything, e.g. `Training log`.
3. **Redirect URI**, exactly:
   ```
   https://training-log.pages.dev/api/whoop/callback
   ```
   using your actual address. **Must match character-for-character** what the app sends later — `https://`, no trailing slash.
4. Scopes: at least `read:recovery`, `read:cycles`, `read:sleep`, `read:profile`, and `offline` (this last one lets it refresh the connection without you re-approving hourly).
5. Save. You get a **Client ID** and a **Client Secret** — copy both somewhere temporary; the secret is shown only once or twice.

### B. Add the credentials to Cloudflare

1. Project **Settings → Environment variables** (Production).
2. `WHOOP_CLIENT_ID` — paste it, plain text is fine.
3. `WHOOP_CLIENT_SECRET` — paste it, but **toggle this one as an encrypted secret**, not plain text. Look for a "Secret" toggle or separate button — unlike the Access variables, this one's a real credential.
4. Save, then redeploy (edit a file on GitHub and commit, same as Stage 11).

The database tables for this already exist from Stage 8 — nothing more to run there.

### C. Connect it

1. Open the app → **Setup**. A **WHOOP** panel shows *Not connected* with a **Connect WHOOP** button.
2. Tap it — you're sent to WHOOP's own login/consent screen. Approve the requested permissions.
3. You land back on Setup with a toast saying *WHOOP connected*, and the panel shows your latest recovery reading.
4. **Today** now has a **Recovery** panel — recovery, strain, sleep, HRV, resting heart rate. Low recovery adds a note about which parts of the day have room to back off.

**Still says "Not connected" after approving?** The redirect URI in Step A doesn't exactly match your real address — check for a typo or a stray trailing slash.

**Error before you even reach WHOOP's approval screen?** `WHOOP_CLIENT_ID` is wrong or wasn't saved.

Recovery only exists once a sleep cycle finishes, so early in the morning it may say *no data yet today* rather than showing yesterday's number. Strain accumulates through the day and only finalizes at midnight.

**Disconnecting:** Setup → **Disconnect**. Deletes the stored connection and asks WHOOP to revoke it on their side too. Reconnecting later is the same three taps.

---

## Making changes later

1. If you touched `app.js`, `app.css`, `sync.js`, `whoop.js`, or `index.html`: open `sw.js` on GitHub, find:
   ```
   const CACHE = 'bnb-v4';
   ```
   Bump it to the next number. **This matters** — without it, your phone keeps serving the old cached version and you'll think your edit didn't work.
2. Edit the file directly on github.com — tap the pencil icon, make your change, **Commit changes**. Cloudflare redeploys automatically within a minute or two.
3. Fully close and reopen the app on your phone (switching away and back isn't always enough to pick up a new service worker).

---

## Troubleshooting

| What you're seeing | Likely cause | What to do |
| --- | --- | --- |
| "Create new file" won't accept a path with slashes | Mobile keyboard autocorrecting the slash | Type the filename first with no path, then manually add `functions/` or `functions/api/` in front before committing |
| Cloudflare build fails immediately | Build output directory wasn't `/`, or a framework preset was picked | Project → Settings → Builds & deployments → check both match Stage 6 |
| Site deploys but looks broken or unstyled | A file's content got mangled during copy-paste | Re-open the file on GitHub, compare its length to the original, recreate it if unsure |
| App loads but Setup says "not behind Access" | Access application hostname doesn't exactly match your real URL | Recheck the subdomain/domain fields for typos |
| Login works for you, not for a friend | Their email isn't in the policy | Add their address as another Emails rule |
| Setup says "SYNC NOT CONFIGURED" | Variable name misspelled, or no redeploy since adding it | Recheck `ACCESS_TEAM_DOMAIN` / `ACCESS_AUD` exactly, redeploy |
| Setup says "LOCAL ONLY" | The `functions` folder wasn't uploaded | Confirm every file under `functions/` exists in the repo, redeploy |
| Data on one device missing on another | Signed in with two different emails | Sign out, sign in with the same address on both |
| Login screen appears but never lets you through | You added a custom domain later, but Access is only set up for `pages.dev` (or vice versa) | Create a second Access application for the other hostname |
| Phone shows an old version after an edit | Service worker still serving the cached copy | Bump `CACHE` in `sw.js`, redeploy, fully close and reopen the app |
| WHOOP: "Not connected" persists after approving | Redirect URI mismatch | Recheck for a typo or stray trailing slash, both places |
| WHOOP: error before reaching the approval screen | `WHOOP_CLIENT_ID` wrong or unsaved | Recheck the value, confirm you redeployed |
| WHOOP: was connected, now isn't, unexpectedly | Access was revoked from WHOOP's own account settings | Reconnect from Setup — expected, not a bug |

---

## Where everything actually lives

- **The app's files** — Cloudflare Pages, served from Cloudflare's network, deployed automatically from your GitHub repo on every commit.
- **The login gate** — Cloudflare Access, in front of the whole site; Cloudflare handles your email and the codes.
- **The API that reads and writes your log** — `functions/api/state.js`, running as a Cloudflare Worker.
- **WHOOP, if connected** — `functions/api/whoop/*`; your recovery/strain/sleep are fetched server-side using a token stored in D1, never sent to or kept in the browser.
- **Your actual training data** — one row in a D1 database (SQLite, hosted in Western Europe), plus a copy cached on-device for offline use.

Free-tier ceilings are far beyond what a personal log needs — 100,000 API requests a day, 5 GB of database storage, against roughly 50 requests a day and a few hundred kilobytes of real data. Nothing here needs watching.
