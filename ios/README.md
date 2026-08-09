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
  Views/                   SwiftUI
BrandNewBodyTests/         the maths, ~70 cases
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

- **WHOOP is gone.** Its OAuth flow needed a server to hold the client secret
  and rotate refresh tokens, and this app has no server. Recovery is a number
  you type on Today. Everything downstream — the deload signal, the recovery
  chart — is unchanged, because it only ever read a percentage out of the
  record. Bringing WHOOP back means either a small backend or a switch to
  HealthKit; nothing else would have to move.
- **Cloudflare Access and the sync API are gone**, replaced by iCloud. So are
  the tombstones and the server-side merge, for the reason above.
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
