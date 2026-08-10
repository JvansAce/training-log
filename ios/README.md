# Brand New Body & Mind — iOS

A native SwiftUI port of the [training-log](../README.md) PWA. Local storage is
SwiftData; the iCloud backup is CloudKit, automatic, and configured rather than
coded.

Open `BrandNewBody.xcodeproj`, set a team, run. Requires Xcode 16 and iOS 17.

---

## What this is

The web app is a single-page PWA backed by `localStorage` plus a Cloudflare
Worker that merges state server-side. This is the same programme — the same
schedule, the same maths, the same opinions — rebuilt as a real iOS app, with
Apple's sync stack in place of the Worker.

Both programmes are here: **Body** (four lifting days, tennis, cardio, the
pyramid) and **Mind** (seven practices that unlock one at a time, the Saturday
ladder, the charisma drills).

## How it is put together

```
BrandNewBody/
  BrandNewBodyApp.swift    @main, the container, the midnight refresh
  Core/                    pure functions over one value type — no UI, no database
  Plan/                    the programme as data: schedule, practices, drills
  Store/                   SwiftData models, the CloudKit container, AppStore
  Whoop/                   OAuth, PKCE, Keychain, WHOOP's API — no health data touches Store
  Views/                   SwiftUI
BrandNewBodyTests/         the maths, plus WHOOP's PKCE and date-matching logic
```

The important line is between `Core` and everything else. Every derived number
— the least-squares weight trend, the progression target, the green streak, the
deload signal, the unlock gate — is a pure function of a single `LogState`
struct, and `LogState` carries its own `today` rather than reading the clock.
That is what makes the test suite possible without standing up a model
container, and it is why a question like *"what does this log look like on the
Thursday after a fortnight in Spain"* is one line to ask.

`AppStore` is the only thing that touches SwiftData. Views read
`store.state` — one immutable snapshot — and call methods to change it.

## Storage and iCloud

Local storage is SwiftData. iCloud is one line:

```swift
ModelConfiguration(storeName, schema: schema, cloudKitDatabase: .automatic)
```

That mirrors every model to the user's **private** CloudKit database. It is
automatic, encrypted in transit, included in their iCloud backup, and shared
across their devices. No account to create, no server, and nothing sent
anywhere the user doesn't already own. There is no sync code in this app
because there is none to write.

**The schema is deliberately fine-grained** — one record per day, per lift-day,
per practice-day. The web version synced the whole log as a single JSON blob,
which is why it needed several hundred lines of server-side merge logic *and* a
tombstone system to make deletion work at all. Small records make CloudKit's
per-record last-writer-wins do the same job for free: a set logged on the phone
in the garage and a weigh-in typed on the iPad upstairs touch different records
and both survive, and deletions propagate properly instead of being resurrected
by the next sync.

CloudKit imposes three constraints, and they explain most of `Models.swift`:
every property needs a default, `.unique` is unsupported (so `AppStore`
enforces one-row-per-day on write), and relationships must be optional — this
schema has none at all.

If the container can't reach CloudKit — no Apple Account, missing entitlement,
a development build — it falls back to a local-only store and Setup says so
plainly rather than claiming a backup that isn't happening.

## Setting up signing and iCloud

The project builds unsigned as-is, but iCloud needs five minutes of setup:

1. **Signing & Capabilities → Team.** Pick yours. `DEVELOPMENT_TEAM` is
   deliberately empty in the project file so it isn't carrying someone else's.
2. **Change the bundle identifier** from `de.playace.brandnewbody` to something
   in your own namespace, if you like.
3. **+ Capability → iCloud**, tick **CloudKit**, and select or create the
   container `iCloud.<your bundle id>`. Then update the identifier in
   `BrandNewBody/BrandNewBody.entitlements` to match.
4. **+ Capability → Background Modes → Remote notifications.** Optional. Without
   it sync still works; it just catches up when the app opens rather than
   arriving while it is in your pocket.
5. **+ Capability → Push Notifications** if you want that to be instant.

CloudKit schema deployment: on first run the debug container creates its record
types automatically. Before shipping, promote the schema from Development to
Production in the [CloudKit Console](https://icloud.developer.apple.com) —
a TestFlight or App Store build against an undeployed schema syncs nothing and
reports no error, which is the single most common way this goes wrong.

## Getting to TestFlight

Needs a paid Apple Developer Program membership — TestFlight isn't available on
a free account, and neither is the iCloud capability.

1. **Team.** Signing & Capabilities → Team. `DEVELOPMENT_TEAM` is empty in the
   project on purpose.
2. **iCloud container.** + Capability → iCloud → tick CloudKit → **+** under
   Containers → `iCloud.<your bundle id>`. Xcode registers it and wires up the
   App ID. Update `BrandNewBody/BrandNewBody.entitlements` if you chose a
   different identifier — a mismatch fails at *signing* time, not build time,
   which makes it confusing to diagnose. Container identifiers are permanent and
   globally unique, so don't type a throwaway name.
3. **Push Notifications** (optional). Without it sync still works, it just
   catches up when the app opens rather than arriving while the phone is in your
   pocket. `UIBackgroundModes: remote-notification` is already declared, and is a
   no-op until this capability exists.
4. **Deploy the CloudKit schema to Production.** ← the one that will bite you.
5. App Store Connect → new app record → answer **App Privacy** (this app is
   genuinely "Data Not Collected": nothing leaves the device except to the
   user's own iCloud, and there are no third-party SDKs).
6. Destination **Any iOS Device (arm64)** → Product → Archive → Distribute App →
   App Store Connect → Upload. Bump `CURRENT_PROJECT_VERSION` every upload;
   build numbers can't repeat within a version.
7. Internal testers (up to 100, on your team) need no review and can install as
   soon as processing finishes. External testers need Beta App Review on the
   first build.

### Why step 4 is the one that bites

TestFlight and App Store builds talk to the **production** CloudKit
environment; debug builds talk to **development**. They hold separate schemas.
A TestFlight build against an undeployed production schema **syncs nothing and
reports no error** — it simply looks as though the app lost the data that is
sitting on your other device.

So: run once in Debug on a real device so SwiftData creates the record types,
then [CloudKit Console](https://icloud.developer.apple.com) → your container →
**Deploy Schema Changes** → Development → Production. Repeat this every time you
add a `@Model` or a property to one.

`INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` is already set, so the export
compliance question won't be asked on each upload. It is accurate: the app uses
only Apple's own crypto, via CloudKit.

## Tests

`⌘U`, or:

```bash
xcodebuild test -project BrandNewBody.xcodeproj -scheme BrandNewBody \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The suite covers the ported maths rather than the screens — the least-squares
fit against a known slope, the rolling 28-day window, the weigh-ins dropped
around illness, the Mifflin-St Jeor calorie basis, progression and layoff
targets, plate maths, the stall check, pyramid totals and vest weeks, the green
streak's deload and time-off behaviour, every deload trigger and suppressor,
build targets, and the Mind unlock gate.

## What changed on the way across

Faithful except where the platform forced a decision:

- **WHOOP connects, but not through Cloudflare Access.** It's real OAuth
  against WHOOP, not a manual field — see **WHOOP** below for the shape of it
  and what you need to configure. Manual entry is still there underneath as a
  fallback for anyone without a WHOOP.
- **Cloudflare Access and the sync API are gone**, replaced by iCloud, except
  for the two narrow WHOOP endpoints described below. So are the tombstones
  and the server-side merge, for the reason above.
- **The service worker, the version banner and the install prompt are gone.**
  The App Store is the update mechanism now.
- **Two charts were redrawn**, not restyled. The web version coloured a week
  containing days off `#4C5878` and a bad week `#2E3750`: two blues 12.4 ΔE
  apart, below the threshold at which *normal* colour vision separates them,
  and the second sat at 1.36:1 against the panel — a bad week read as no week
  at all. Time off is now a hatch rather than a hue, so it survives colour
  blindness and a dark gym, and the low-session step is one you can actually
  see. The recovery chart gained a legend so its three bands aren't carried by
  colour alone.
- **Fixed dark, no light mode.** The app is read at arm's length in bad light,
  and the design — bone on near-black, one red accent — was drawn for that. A
  light mode would be a different design, not a recolouring.
- **The app icon is rendered from `icon.svg`** at 1024px by
  `scripts/render_icon.py`, so the two versions carry the same mark.

## WHOOP

WHOOP's OAuth is a confidential-client flow: exchanging a code (or a refresh
token) for an access token needs `WHOOP_CLIENT_SECRET`, and that secret must
never ship inside an app binary — anyone could extract it and impersonate this
app to WHOOP. So a server is unavoidable for that one step. What it doesn't
need to be is the *same* server the web app uses, protected the *same* way.

**The split.** Two new, narrow, stateless Cloudflare Pages Functions —
`functions/api/whoop/exchange.js` and `functions/api/whoop/refresh.js` — exist
for exactly the calls that need the secret. They hold no D1 row and don't call
`identify()`; unlike every other function in `functions/api/`, they don't know
or care who's asking. Every actual data read — recovery, cycle, sleep,
workout — goes device-to-WHOOP directly from the app with the access token, so
no health data passes through anything this project runs, only the tokens do,
and only at connect and refresh time. Tokens themselves live in iCloud
Keychain (`Whoop/KeychainStore.swift`), not in SwiftData — a credential belongs
in the platform's credential store, not alongside training logs.

**The redirect.** `ASWebAuthenticationSession` opens WHOOP's consent page and
catches the return via a custom URL scheme
(`Whoop/WhoopClient.swift` + the app's `Info.plist`), protected with **PKCE**
(`Whoop/PKCE.swift`). This isn't the more obvious-looking choice — Universal
Links, verified against a domain you own, sound like the safer redirect — but
RFC 8252 is specific about why that's not actually where the safety comes
from: a private-use scheme *can* be registered by more than one app, so PKCE,
not domain ownership, is what makes an intercepted authorization code useless
to whoever intercepted it. Universal Links add real setup cost (Associated
Domains, a hosted `apple-app-site-association` file, `webcredentials`) for a
marginal gain once PKCE is already doing the actual work.

### Setup

1. **Carve the two endpoints out of Cloudflare Access.** Access fronts the
   whole hostname the web app is deployed to, and it authenticates *browser
   sessions* — a native app calling `/api/whoop/exchange` directly gets
   Access's login page back instead of JSON, which looks exactly like a WHOOP
   problem and isn't one. Zero Trust → your Access application → Policies →
   add a **Bypass** policy scoped to `/api/whoop/exchange` and
   `/api/whoop/refresh`.
2. **Register the app's redirect URI on the WHOOP developer dashboard**,
   alongside the web app's `https://…/api/whoop/callback` —
   `de.playace.brandnewbody.whoop://callback`. Most dashboards accept more
   than one redirect URI per app; if yours doesn't, this needs its own WHOOP
   developer app and its own client ID/secret pair, set as a second
   environment variable pair on the Pages project.
3. **Fill in `ios/BrandNewBody/Whoop/WhoopConfig.swift`** — `workerBaseURL`
   (where the Pages project is deployed) and `clientID` (the same value as
   `WHOOP_CLIENT_ID`, not a secret — it's already public in the authorize
   URL). Connect WHOOP stays disabled with a clear message in Setup until
   both are real values.
4. Optional: set `WHOOP_APP_TOKEN` on the Pages project and the same string as
   `WhoopConfig.appToken`, to require a shared header on the two endpoints.

### The residual risk, stated plainly

Because the two endpoints don't check identity, someone could call them with
an authorization code they separately obtained by going through WHOOP's own
consent screen for *their own* WHOOP account. The worst that does is connect
their account through this app's registered WHOOP developer app — spending
its rate limit, never touching anyone's data. `WHOOP_APP_TOKEN` above is a
cheap deterrent against that, not a security boundary; a constant baked into
the app binary can be extracted by anyone who tries. Worth having if this app
is ever used by more than a handful of people, not essential for one.

## Editing the plan

Same as the web app: it is all data.

- `Plan/Schedule.swift` — one `TrainingDay` per weekday (`0` = Sunday). Give an
  exercise a `liftID` for inline `kg × reps` logging; leave it off for
  warm-ups. Set `restSeconds` on a day and the rest-timer button appears.
- `Plan/MindPlan.swift` — practices, unlock weeks, charisma drills, ladder,
  journal prompts.
- `Core/Fuel.swift` — the calorie and macro maths.

The prescription string is parsed for progression targets (`4 × 8–10`), so the
programme text stays the single source of truth rather than being duplicated
into a table that can drift. Anything that isn't a clean numeric range —
`4 × max reps` — correctly gets no target.

### What editing the plan does to days already logged

There is no plan versioning: history stores *references* into the plan and is
rendered through whatever the plan says today. Mostly that is what you want —
fix a typo and it is fixed everywhere — but it means some edits rewrite the
past. **Treat `key` and `liftID` as permanent identifiers and you are safe.**

Free to change:

- **Renaming** an exercise, its note, tag or prescription. The key is unchanged,
  so past ticks still bind; the past day simply displays the new text.
- **Adding** an exercise. Past days show it unticked, but a completed session is
  decided by *how many* items were ticked, not which, so nothing is
  de-certified.
- **Removing** one. Its past ticks become invisible orphans but still count, so
  past sessions stay certified.

Rewrites the past:

- **Changing an item's `key`** — every past tick for it orphans and it reads as
  never done.
- **Changing a `liftID`** — the whole per-set history detaches and the lift reads
  as never trained. (Two exercises *sharing* an id merge their histories, which
  is what `lat` and `calf` do deliberately.)
- **Growing a short day past three items** — `Consistency.sessionNeed` is
  `min(3, items.count)`, so Thursday's two items mean two ticks complete it. Add
  two more and the bar becomes three, and every past Thursday with exactly two
  ticks retroactively stops counting — which can break a green streak already
  banked. The only edit here that can take something away from the user.
- **Reordering `MindPlan.practices`** — `mindUnlocked` is a count, so inserting
  mid-list changes which practices someone has, and the adherence gate
  recomputes over the new set against old logs.
- **Reordering `MindPlan.charisma` or `MindPlan.ladder`** — drill and rung ticks
  are keyed by position (`chr7`, `rung3`), so inserting one re-points history at
  a different technique. Append, don't insert.

Two things are immune. The **pyramid** snapshots the cap and vest load in force
when it was ticked, so its history survives any later change to the rules. And
the **weight trend, fuel maths, build targets, deloads and time off** never read
the plan at all — though note `Fuel.basis` hardcodes rest days as day 0 and 4,
so moving the rest day in `Plan` would not move the calorie target with it.

`Plan.mobility` used to be the exception — its ticks were stored as positions,
so inserting a drill silently re-pointed every past tick. It is keyed now, with
`Plan.mobilityKey(legacyIndex:)` translating anything already recorded, and
`testMobilityKeysAreStableAndUnique` fails if the frozen legacy order and the
live list ever drift apart.
