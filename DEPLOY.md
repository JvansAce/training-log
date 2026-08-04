# Deploying the training log — the very detailed version

This assumes you've never touched Cloudflare Pages, Wrangler, D1 or Access before. Every step says exactly what to click and what you should see afterward, so if something looks different on your screen, that's your signal something went wrong — stop and check, rather than pushing on and getting confused three steps later.

Written for a Mac, since that's what you're on. Where a step is Mac-specific I've said so.

**Time:** 30–45 minutes, done in one sitting.
**Cost:** €0.

---

## Two ways to do this

Everything from **Stage 5 onward** (setting up your team, creating the login, the environment variables) happens entirely in a web browser and is identical either way you choose.

The only parts that normally need a computer are getting the files hosted and creating the database. Cloudflare has a browser-only way to do both of those too — so this is genuinely doable start to finish on an iPhone, no Mac and no Terminal required.

- **On a Mac, don't mind Terminal?** Follow **Stages 1–4** below as written.
- **iPhone only, or just want to skip the command line?** Skip straight to **"Doing this entirely on an iPhone"**, then rejoin this document at **Stage 5** — everything from there is the same regardless of which path you took.

---

## Before you start

### Create a Cloudflare account

1. Open a browser, go to **dash.cloudflare.com**.
2. Click **Sign up**.
3. Enter your email and a password. Verify the email if asked.
4. You'll land on an empty dashboard. That's it, no payment details needed anywhere in this walkthrough.

### Check Node.js is installed

1. Open **Terminal**: press `Cmd + Space`, type `Terminal`, press Enter. A window with a text prompt appears.
2. Type this and press Enter:
   ```
   node -v
   ```
3. **If you see something like** `v20.11.0` **or any `v18` or higher** — good, skip to the next section.
4. **If you see** `command not found: node` — Node isn't installed. Do this:
   - Go to **nodejs.org** in your browser.
   - Click the big green button (it'll say something like "20.x.x LTS").
   - Open the downloaded `.pkg` file, click through the installer with the default options (Continue → Continue → Agree → Install), enter your Mac password when asked.
   - Close Terminal completely and reopen it (`Cmd+Q` on Terminal, then reopen).
   - Run `node -v` again. It should now show a version number.

---

## Stage 1 — Get the project files onto your computer

1. Find the file you downloaded from this conversation — probably in your **Downloads** folder, likely named something like `training-log.zip` or a folder called `training-log`.
2. If it's a `.zip`: double-click it in Finder. It unpacks into a folder next to it.
3. In Terminal, navigate into that folder. If it's in Downloads:
   ```
   cd ~/Downloads/training-log
   ```
4. Confirm you're in the right place:
   ```
   ls
   ```
   You should see a list including `index.html`, `app.js`, `app.css`, `functions`, `schema.sql`, `sw.js`, `manifest.webmanifest`. If `ls` shows nothing or an error, you're in the wrong folder — check the exact path in Finder (right-click the folder → Get Info → the path is listed there) and `cd` to that instead.

**Keep this Terminal window open and stay in this folder for the rest of the walkthrough.** Every command below assumes you're still here.

---

## Stage 2 — Install Wrangler and log in

Wrangler is Cloudflare's command-line tool — it's how you'll create the database and upload the site.

1. Install it:
   ```
   npm install -g wrangler
   ```
   This takes 10–30 seconds and prints a bunch of lines ending in something like `added 120 packages in 8s`.

   **If you see a permissions error** (`EACCES`, or "permission denied"), your Mac's npm is set up to need admin rights for global installs. Run it with `sudo` instead:
   ```
   sudo npm install -g wrangler
   ```
   It'll ask for your Mac password (typing produces no dots or stars — that's normal, just type it and press Enter).

2. Confirm it installed:
   ```
   wrangler --version
   ```
   Should print something like `⛅️ wrangler 3.x.x`.

3. Log in:
   ```
   wrangler login
   ```
   Terminal prints a URL and should automatically open your default browser to a Cloudflare page asking **"Allow Wrangler to make changes to your account?"** Click the blue **Allow** button.

   Back in Terminal, you should see **`Successfully logged in.`**

   **If the browser doesn't open automatically**, copy the URL Terminal printed and paste it into your browser manually.

4. Confirm you're logged in:
   ```
   wrangler whoami
   ```
   Prints your account email and an Account ID (a long string of letters and numbers). You don't need to write this down.

---

## Stage 3 — Create the database

Still in the same Terminal window, same folder:

```
wrangler d1 create training-log --location weur
```

`--location weur` pins the database to Western Europe. **This can't be changed later without deleting and recreating the database**, so don't skip that flag.

You'll see output like:

```
✅ Successfully created DB 'training-log' in region WEUR
[[d1_databases]]
binding = "DB"
database_name = "training-log"
database_id = "a1b2c3d4-....."
```

You don't need to copy the `database_id` — you'll select the database by name later through the dashboard. If you want to keep the output somewhere just in case, that's fine too.

Now create the table inside it:

```
wrangler d1 execute training-log --remote --file=./schema.sql
```

**The `--remote` flag is essential.** Without it, Wrangler quietly writes to a fake local copy on your own laptop instead of the real database, and you'll spend the rest of this walkthrough confused about why nothing shows up.

Expected output: a few lines ending in something like `Executed 1 command in X ms`.

**Check it worked:**

```
wrangler d1 execute training-log --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
```

You should see a small table printed with one row: `state`. If the output is empty, you forgot `--remote` on the previous command — run it again with the flag.

---

## Stage 4 — Deploy the site for the first time

```
wrangler pages deploy .
```

(Note the space and the dot at the end — that dot means "this folder".)

Wrangler will ask you a series of questions, one at a time. Type your answer and press Enter after each:

1. **"Would you like to create a new project?"** → type `y`, press Enter.
2. **"Enter the name of your new project:"** → type something short and simple, like `training-log`. This becomes part of your web address, so avoid spaces or special characters — letters, numbers, and hyphens only.
3. **"Enter the production branch name:"** → just press Enter to accept the default (`main`).

It then uploads your files — you'll see a progress indicator and a list of files being uploaded. This takes 10–60 seconds depending on your connection.

At the end, you'll see:

```
✨ Deployment complete!
https://training-log.pages.dev
```

**This URL is your app's permanent address**, whether or not you ever add a custom domain later. Write it down or bookmark it.

### Check it worked

1. Open that URL in your browser.
2. You should see the dark app load, with **"BRAND NEW BODY"** as the big heading and today's date underneath.
3. Tap **Setup** at the bottom.
4. It will say something like *"this copy is not behind Cloudflare Access"* and the small text at the bottom of the page will read `LOCAL ONLY` or `SYNC NOT CONFIGURED`. **Both are correct right now** — you haven't set up login or the database connection yet. That comes in the next stages.

**If the page is blank or broken:** right-click anywhere on the page → **Inspect** → click the **Console** tab at the top of the panel that opens → look for a red error message, which will tell you what went wrong.

---

## Doing this entirely on an iPhone (no computer, no Terminal)

This replaces Stages 1–4 above. Once you finish this section, jump straight to **Stage 5** further down — nothing else in this document changes.

The trick is: instead of Wrangler pushing files from a terminal, you put the files in a GitHub repository and tell Cloudflare to watch that repository. Every time you edit a file on GitHub, Cloudflare notices and redeploys automatically. And instead of a terminal command creating the database, Cloudflare's dashboard has a **Console** tab that runs SQL directly — no CLI involved.

**Use Safari, not the GitHub app**, for the file-creation steps below. The GitHub app doesn't support creating new files, but the ordinary github.com website works fine in mobile Safari — it's just a web form.

### A. Get the project files onto your iPhone

1. Open Safari, and download the project zip from wherever you got it (the same download link from this conversation works fine on the phone).
2. Open the **Files** app, find the downloaded `.zip` in **Downloads**.
3. Tap it once — iOS unzips it automatically into a folder of the same name, right there in Files.
4. Open that folder and confirm you see `index.html`, `app.css`, `app.js`, `sync.js`, `sw.js`, `manifest.webmanifest`, `schema.sql`, a `functions` folder, and the icon files.

### B. Create a GitHub account and a repository

1. In Safari, go to **github.com**, tap **Sign up** if you don't already have an account. It's free.
2. Once signed in, tap the **+** icon (top right) → **New repository**.
3. Name it something simple, e.g. `training-log`.
4. Leave it **Public** (a private repo needs a paid plan to deploy from with Cloudflare Pages' free tier — being public here just means someone would need the exact repo name to find your source code, not your training data, which lives in the database, not the repo).
5. Tick **Add a README file** so the repo isn't empty. Tap **Create repository**.

### C. Add the small text files by pasting them in

For each of these files, you'll create it directly on GitHub and paste its contents. In the repo, tap **Add file → Create new file**.

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
- `functions/_shared.js` — **type the full path including the slash** in the filename box. GitHub creates the `functions` folder for you automatically.
- `functions/api/state.js`
- `functions/api/whoop/authorize.js`
- `functions/api/whoop/callback.js`
- `functions/api/whoop/today.js`
- `functions/api/whoop/disconnect.js`

For each one:

1. Type the filename (or full path, for the ones with slashes) into the **Name your file...** box.
2. Go back to the **Files** app on your phone, open that same file (tapping a text file previews it), tap and hold to **Select All**, then **Copy**.
3. Switch back to Safari, tap into the big empty text box, and **Paste**.
4. Scroll down, tap **Commit changes...**, then **Commit changes** again to confirm.

This is the tedious part — fifteen files, one at a time — but each one takes under a minute. The WHOOP ones only matter if you plan to do Stage 10 later; skip them for now if you're not sure yet; you can always add them the same way afterward.

### D. Upload the two icon images

PNGs can't be pasted as text, so these use a different button.

1. In the repo, tap **Add file → Upload files**.
2. Tap **choose your files**, which opens the file picker — navigate to your unzipped folder in Files, and select both `icon-192.png` and `icon-512.png` (tap **Select** in the top right of Files to enable picking more than one at once).
3. Scroll down, **Commit changes**.

### E. Check everything's there

Go to the repo's main page. You should see all the files listed, with the `functions` folder showing a little folder icon. Tap into `functions → api` and confirm `state.js` and a `whoop` folder are there, then into `whoop` and confirm its four files. If something's missing, repeat step C or D for just that file.

### F. Connect Cloudflare Pages to the repository

1. In Safari, go to **dash.cloudflare.com**, sign in (or create the account now if you haven't — same as in "Before you start" above).
2. **Workers & Pages** in the sidebar → **Create** → **Pages** tab → **Connect to Git**.
3. Authorize Cloudflare to access your GitHub account when prompted — this is a standard GitHub permission screen, tap **Authorize**.
4. Select your `training-log` repository from the list.
5. On the build settings screen:
   - **Framework preset:** None
   - **Build command:** leave empty
   - **Build output directory:** `/`
6. Tap **Save and Deploy**.

Cloudflare builds and deploys the site — since there's no actual build step, this takes well under a minute. You land on a page with your live URL, something like `https://training-log.pages.dev`.

**Check:** open that URL. The app should load, same as described in the Mac walkthrough's Stage 4 check.

**From now on, any time you edit a file on GitHub and commit the change, Cloudflare automatically redeploys within a minute or two.** There's no separate "push" step to remember — this is actually simpler than the Mac path for ongoing edits.

### G. Create the database — no CLI needed

1. Still in the Cloudflare dashboard, find **Workers & Pages** in the sidebar, then look for **D1 SQL Database** as its own entry (it's a sibling to Workers & Pages, not nested under your project).
2. Tap **Create Database**.
3. Name it `training-log`.
4. Under **Location hint**, choose **Western Europe (weur)** — same reasoning as the Mac path: this can't be changed later without recreating the database.
5. Tap **Create**.

### H. Run the schema — also no CLI needed

1. Open the database you just created, find the **Console** tab.
2. Open `schema.sql` in your Files app (or scroll back up to where you pasted it into GitHub, and view it there), copy its contents — it's short, just one `CREATE TABLE` statement.
3. Paste it into the Console's query box, tap **Run** (or the equivalent send/execute button).
4. You should see a success message, no rows returned.

**Check:** in the same Console, type:
```
SELECT name FROM sqlite_master WHERE type='table'
```
Run it. You should see one row: `state`.

---

**You're done with the computer/CLI-only part.** Continue directly to **Stage 5** below — the Zero Trust setup, the Access application, the environment variables, and everything after that is identical whether you got here via Terminal or via Safari.

The one difference to remember for later: in the Mac walkthrough, "redeploy" means running `wrangler pages deploy .` again. On the iPhone path, "redeploy" just means editing the relevant file on GitHub and committing — Cloudflare picks it up automatically.

---

## Stage 5 — Set up your Cloudflare team (one-time, for Access)

This is a one-time setup for your whole Cloudflare account, not just this project.

1. In the Cloudflare dashboard, look at the left sidebar. Find **Zero Trust** (it may show as its own icon, or be under a section — Cloudflare has renamed this a few times, so if you don't see "Zero Trust" directly, look for **Access** or **Zero Trust & Access**).
2. First time in, it'll ask you to **choose a team name**. This becomes part of a URL: `yourteamname.cloudflareaccess.com`. Pick something short, lowercase, no spaces — e.g. your first name plus a word, like `jonastraining`.
3. **Write this team name down somewhere.** You'll need to type it exactly, including the `.cloudflareaccess.com` part, into an environment variable in Stage 7.
4. Confirm — there's nothing else to configure on this screen, just click through.

### Turn on email login codes

1. Still in Zero Trust, find **Settings** in the sidebar → **Authentication**.
2. Look for a section called **Login methods**.
3. Check whether **One-time PIN** is already listed.
   - **If it's there:** nothing more to do.
   - **If it's not there:** click **Add new**, find **One-time PIN** in the list that appears, select it. No further configuration needed — click through and save.

---

## Stage 6 — Create the Access application (the actual login gate)

1. Still in Zero Trust, find **Access controls** in the sidebar (older dashboards just call this **Access**) → **Applications**.
2. Click **Create new application** (sometimes just a **+ Add an application** button).
3. Choose **Self-hosted** — it's usually the first option, with a description like "Protect a website with Cloudflare Access."

### Fill in the application details

1. **Application name** — type anything descriptive, e.g. `Training log`.
2. **Session duration** — this dropdown defaults to something short like **24 hours**. Change it to **1 month**. If you leave it at 24 hours, you'll be typing in an email code before almost every workout, which gets old fast.
3. Scroll down to **Public hostname**. This is the important part — it tells Cloudflare which web address to protect.
   - There's a **Subdomain** field and a **Domain** dropdown, plus an optional **Path** field.
   - In **Subdomain**, type your project name — the same one you chose in Stage 4, e.g. `training-log`.
   - In the **Domain** dropdown, `pages.dev` may already be listed as an option — if so, select it. If it's *not* in the dropdown, look for a link or toggle that says something like **"Switch to custom input"** or **"enter a custom domain"**, click it, and type the full address exactly: `training-log.pages.dev`.
   - Leave **Path** empty — that protects the whole site, not just one page.
4. Click **Next** or **Continue** to move to policies.

### Create the policy (who's allowed in)

1. **Policy name** — type `Me` or anything similar.
2. **Action** — leave this on **Allow**.
3. Under **Rules**, you'll see a section for **Include** with a dropdown labeled **Selector**. Change it to **Emails**.
4. A text box appears — type your email address exactly.
5. If you want someone else to have access too (a partner, a coach), click **Add include** or the **+** button and add another **Emails** rule with their address. Rules in the same policy are combined with OR, meaning either address gets in.
6. Click **Save policy**, then **Add application** or **Create** to finish creating the whole application.

### Copy the AUD tag — you need this in Stage 7

1. After creating the application, you land on its **Overview** page (or click into it from the Applications list if not).
2. Look for a field labeled **Application Audience (AUD) Tag** — it's a long string of letters and numbers, something like `a1b2c3d4e5f6...`.
3. Click the small copy icon next to it, or select and copy the text manually.
4. **Paste it somewhere temporary** — a Notes app, a blank Terminal line you won't press Enter on, anywhere you can retrieve it in five minutes.

### Also protect the preview URLs

Separately from the application you just made, Cloudflare Pages generates random preview addresses every time you redeploy (like `a1b2c3.training-log.pages.dev`), and by default those are public even once your main URL is locked down.

1. Go to **Workers & Pages** in the main dashboard sidebar (not Zero Trust — the regular dashboard) → click your `training-log` project.
2. **Settings** → **General**.
3. Find **Access policy**, click **Enable**.

This creates a second, separate Access application automatically, scoped to the preview addresses. You don't need to configure anything else here.

### Check the login actually works

1. Open a **private/incognito browser window** (Cmd+Shift+N in Chrome, Cmd+Shift+N in Safari is actually Cmd+Option+P — either way, use your browser's private mode so you're not still logged into anything).
2. Go to `https://training-log.pages.dev` (your actual address).
3. You should land on a Cloudflare-branded page asking for your email address, **not** the training app itself.
4. Enter your email, click **Send me a code** (or similar).
5. Check your email — a 6-digit code arrives within a few seconds to a minute.
6. Type the code into the browser, submit.
7. **Now** you should land on the training app.

**If you reach the app directly without any login screen at all** — the hostname on your Access application doesn't exactly match your real URL. Go back into the application settings and double-check the subdomain and domain fields character by character.

---

## Stage 7 — Connect the database and finish configuring

1. Dashboard → **Workers & Pages** → your `training-log` project → **Settings**.
2. Look for **Functions** or **Bindings** in the left-hand tabs within that project's settings (the exact label has changed between Cloudflare dashboard versions — look for anything mentioning "D1" or "Bindings").
3. Find **D1 database bindings**, click **Add binding**.
4. **Variable name** — type exactly `DB` (capital letters, nothing else).
5. **D1 database** — select **training-log** from the dropdown.
6. Click **Save**.

### Add the two environment variables

1. Still in project **Settings**, find **Environment variables** (sometimes under a **Variables and Secrets** tab).
2. Make sure you're adding these to the **Production** environment (there may be a Preview environment too — you can add them there as well, but Production is the one that matters for your real usage).
3. Click **Add variable**, and add these two, one at a time:

   | Variable name | Value |
   | --- | --- |
   | `ACCESS_TEAM_DOMAIN` | the team name from Stage 5, plus `.cloudflareaccess.com` — e.g. `jonastraining.cloudflareaccess.com` |
   | `ACCESS_AUD` | the AUD tag you copied in Stage 6 |

   Type these as **plain text**, not "Encrypt" — neither value is a secret in the way an API key is; they're just configuration.

   **Double-check `ACCESS_TEAM_DOMAIN` has no `https://` in front and no trailing slash** — just the bare hostname.

4. Click **Save**.

### Redeploy — this step is easy to forget

Cloudflare only applies new bindings and variables to deployments made *after* you added them. Your site is currently running the version from Stage 4, which doesn't know about any of this yet.

**If you deployed via Wrangler (Mac path):** do one of these:

- **From the dashboard:** in your project, go to **Deployments**, find the most recent one, click the **⋯** (three dots) menu next to it, choose **Retry deployment**.
- **From Terminal:** go back to your project folder and run the same command as before:
  ```
  wrangler pages deploy .
  ```

**If you connected via GitHub (iPhone path):** open any file in your repo on github.com, make a trivial edit (even just adding a blank line), and commit. That alone triggers a fresh deployment, which now picks up the binding and variables. Or: in the Cloudflare dashboard, **Deployments** → latest one → **⋯** → **Retry deployment**, same as above.

### Check it worked

1. Open your app URL (in a normal window is fine now, or the same private window).
2. Sign in if asked.
3. Go to **Setup**.
4. You should now see:
   - An **Account** panel showing your email address, with a **Sign out** button.
   - A **Sync** panel saying something like *"Your log is on the server."*
   - Small text at the bottom of the screen reading `SYNCED` followed by a time.

**If it still says "not configured":** one of the two variable names is misspelled, or you forgot to redeploy after adding them. Go back and check both, character by character — `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` need to match exactly.

**If it says `LOCAL ONLY`:** the `functions` folder didn't get uploaded. Check that folder still exists inside your project folder in Finder, then redeploy.

---

## Stage 8 — Prove it actually syncs

Worth doing once on purpose, so you trust it later without wondering.

1. On your laptop, in the app, go to **Today**, scroll to **Body weight**, type a number like `79.4`, tap **Log**.
2. Open the app on your phone's browser (same URL). Sign in with your email and a fresh code if asked.
3. That same weight should already be there.
4. On your phone, tick off two of today's exercises.
5. Go back to your laptop and reload the page. The ticks should now show there too.

**If step 3 doesn't show the number:** check you signed in with the exact same email address on both devices. Two different addresses create two completely separate records — which is correct behaviour, just probably not what you meant to do.

---

## Stage 9 — Install it on your phone like an app

**iPhone (Safari):**
1. Open the app's URL in Safari.
2. Tap the **Share** icon (square with an arrow pointing up) at the bottom of the screen.
3. Scroll down, tap **Add to Home Screen**.
4. Tap **Add** in the top right.

**Android (Chrome):**
1. Open the app's URL in Chrome.
2. Tap the **⋮** menu (three dots, top right).
3. Tap **Install app** (or **Add to Home screen**).

Either way, it now opens full-screen with no browser address bar, and the basic app shell is cached, so it opens even with no signal in the gym. Anything you log offline gets pushed to the server automatically once you're back on Wi-Fi or mobile data — the small status text at the bottom of Setup tells you the current state.

---

## Stage 10 (optional) — Connect WHOOP

This adds live recovery, strain and sleep to the Today page, and a warning when recovery is low. Entirely optional — skip it and everything above still works exactly as described.

Needs the same D1 database from Stage 3/G and the same Access setup from Stages 5–7, so do this after those, not instead of them.

### A. Register a WHOOP developer app

1. Go to **developer-dashboard.whoop.com**. Sign in with your regular WHOOP account (you need a WHOOP device and account already — you have one).
2. Create a new app. Name it anything, e.g. `Training log`.
3. Find the **Redirect URI** field and enter exactly:
   ```
   https://training-log.pages.dev/api/whoop/callback
   ```
   (using your actual `pages.dev` address or custom domain — whichever one you actually use to open the app). **This must match character-for-character** what the app sends later, including `https://` and no trailing slash.
4. Under scopes, make sure at least these are selected: `read:recovery`, `read:cycles`, `read:sleep`, `read:profile`, and `offline` (offline is what allows refreshing the connection without you re-approving it every hour).
5. Save. You'll be given a **Client ID** and a **Client Secret**. Copy both somewhere temporary — you need them in the next step, and the secret in particular is shown only once or twice.

### B. Add the credentials to Cloudflare

1. Dashboard → **Workers & Pages** → your project → **Settings → Environment variables** (Production).
2. Add `WHOOP_CLIENT_ID` — paste the Client ID. Plain text is fine.
3. Add `WHOOP_CLIENT_SECRET` — paste the Client Secret, but this time **toggle it as an encrypted secret**, not plain text. Look for a toggle or a separate "Secret" button next to the field — this one's a real credential, unlike the Access variables from Stage 7, which were just configuration.
4. Save.

### C. Add the new database tables

The schema file already includes the WHOOP tables — you're just re-running the same command from Stage 3 (or Stage H if you went the iPhone route), and it's safe to repeat: `CREATE TABLE IF NOT EXISTS` doesn't touch a table that already exists, so your training data is untouched.

**Mac / Wrangler:**
```
wrangler d1 execute training-log --remote --file=./schema.sql
```

**iPhone / dashboard Console:** open the database's **Console** tab, paste the whole `schema.sql` content again, run it.

**Check:**
```
wrangler d1 execute training-log --remote --command "SELECT name FROM sqlite_master WHERE type='table'"
```
Should now list three tables: `state`, `whoop_tokens`, `whoop_oauth_state`.

### D. Redeploy

Same as Stage 7 — new environment variables only apply to deployments made after you added them.

- **Mac:** `wrangler pages deploy .`
- **iPhone:** edit any file on GitHub and commit, or **Deployments → ⋯ → Retry deployment**.

### E. Connect it

1. Open the app, go to **Setup**.
2. You should see a **WHOOP** panel saying *Not connected*, with a **Connect WHOOP** button.
3. Tap it. You're sent to WHOOP's own login/consent page — sign in there if needed, and approve the requested permissions.
4. WHOOP sends you back to the app. You should land on Setup with a toast saying *WHOOP connected*, and the panel now shows your most recent recovery reading.
5. Go to **Today** — a **Recovery** panel now sits near the top, showing recovery, strain, sleep, HRV and resting heart rate. If recovery is in WHOOP's red zone, a note appears telling you which parts of the day have room to back off.

**If Setup still says "Not connected" after you approve on WHOOP's page:** the redirect URI you registered in Step A doesn't exactly match your real address — go back and check for a typo, a missing `https://`, or a trailing slash that shouldn't be there.

**If WHOOP's own page shows an error before you even get to approve anything:** double-check the Client ID matches exactly what's in the Cloudflare environment variable.

### A note on what this can and can't show you

Recovery only exists once a sleep cycle finishes, so first thing in the morning before that's processed, the panel will say *no data yet today* rather than showing a stale number from yesterday. Strain accumulates through the day and only becomes final at midnight — what you see mid-afternoon is a running total, not the day's final figure.

### Disconnecting

Setup → **Disconnect**. This deletes the stored connection from the database and also asks WHOOP to revoke it on their side, so the app stops showing up in WHOOP's own connected-apps list too. Reconnecting later is the same three taps as the first time.

---

## Making changes later

Whenever you edit any of the files:

1. If you touched `app.js`, `app.css`, `sync.js`, or `index.html`: open `sw.js`, find the line near the top that says:
   ```
   const CACHE = 'bnb-v3';
   ```
   Change `v3` to `v4` (or whatever the next number is). **This step matters** — without it, your phone keeps serving the old cached version and you'll think your edit didn't work.

2. **Deployed via Wrangler (Mac path):** back in Terminal, in the project folder:
   ```
   wrangler pages deploy .
   ```

   **Connected via GitHub (iPhone path):** edit the file directly on github.com — tap the pencil icon on the file, make your change, scroll down, **Commit changes**. Cloudflare redeploys automatically within a minute or two; nothing else to run.

3. Give it a minute, then reload the app on your phone (you may need to fully close and reopen it, not just switch away and back).

---

## Troubleshooting

| What you're seeing | Likely cause | What to do |
| --- | --- | --- |
| `command not found: node` | Node.js isn't installed | Install from nodejs.org, restart Terminal |
| `command not found: wrangler` | The global install failed silently, or a new Terminal window doesn't see it | Run `npm install -g wrangler` again, watch for errors this time |
| `EACCES` / permission denied during npm install | Your Mac's npm needs admin rights for global packages | Rerun the same command with `sudo` in front |
| App loads but Setup says "not behind Access" even after Stage 6 | Hostname on the Access application doesn't exactly match your real URL | Recheck the subdomain/domain fields for typos |
| Login works on your test but a friend can't get in | Their email isn't in the policy | Add their address as another Emails rule in the same policy |
| Setup says "SYNC NOT CONFIGURED" | A variable name is misspelled, or you didn't redeploy after adding them | Recheck `ACCESS_TEAM_DOMAIN` and `ACCESS_AUD` exactly, then redeploy |
| Setup says "LOCAL ONLY" | The `functions` folder wasn't included in the deploy | Confirm it exists in your project folder, redeploy |
| `wrangler d1 execute` seems to succeed but nothing shows up later | Forgot the `--remote` flag | Rerun the same command with `--remote` added |
| Phone shows an old version after you edited something | Service worker is still serving the cached copy | Bump the `CACHE` value in `sw.js`, redeploy, fully close and reopen the app |
| Data logged on one device doesn't appear on another | Signed in with two different email addresses | Sign out of one, sign in again with the same address as the other device |
| Login screen appears but never lets you through | You have a custom domain now, but Access is only set up for the `pages.dev` address (or vice versa) | Create a second Access application for the second hostname — each one needs its own |
| (iPhone path) "Create new file" box won't accept the path with slashes | Rare GitHub quirk on some mobile keyboards autocorrecting the slash | Type the filename first without any path, then manually add `functions/` or `functions/api/` in front before committing |
| (iPhone path) Cloudflare build fails immediately | Build output directory wasn't set to `/`, or a framework preset was selected | Project → Settings → Builds & deployments → check both fields match Stage F above |
| (iPhone path) Site deploys but looks broken / unstyled | A file's content got mangled during copy-paste (extra characters, missing lines) | Re-open the file on GitHub, compare its length against the original, recreate it if unsure |
| WHOOP: "Not connected" persists after approving on WHOOP's site | Redirect URI registered with WHOOP doesn't exactly match the app's real address | Recheck for a typo, missing `https://`, or stray trailing slash in both places |
| WHOOP: error page appears before you even reach WHOOP's approval screen | `WHOOP_CLIENT_ID` wrong, or not saved | Recheck the value and that you redeployed after adding it |
| WHOOP: was connected, now shows "Not connected" out of nowhere | Access was revoked from WHOOP's own account settings, not from this app | Reconnect from Setup — this is expected behaviour, not a bug |

---

## Where everything actually lives, for your own reference

- **The app's files** — Cloudflare Pages, served worldwide from Cloudflare's own network.
- **The login gate** — Cloudflare Access, sitting in front of the site; Cloudflare handles your email and the one-time codes.
- **The API that reads and writes your log** — `functions/api/state.js`, running as a Cloudflare Worker.
- **WHOOP, if connected** — `functions/api/whoop/*`, same pattern: your recovery/strain/sleep numbers are fetched server-side using a token stored in D1, never sent to or kept in the browser.
- **Your actual training data** — one row in a Cloudflare D1 database (SQLite, hosted in Western Europe per the `--location weur` flag), plus a copy cached in each device's browser storage for offline use.

Free-tier ceilings are far beyond what a personal training log needs — 100,000 API requests a day and 5 GB of database storage, against roughly 50 requests a day and a few hundred kilobytes of actual data. Nothing here needs monitoring.
