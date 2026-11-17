# Moving a local setup to Kill Cord Cloud

Status: design only, November 16, 2026. Kill Cord Cloud (the paid always-on monitor in `docs/product/spec.md`) is not built and stays out of v1. This doc says how someone who set Kill Cord up on their Mac moves that setup into a cloud account later without pasting a key again, and what had to ship now so that works. Tracking issue: #18.

## Decided (November 16, 2026)

- **Hybrid key model.** By default an account syncs readings only: keys stay on the Mac and the app sends spend readings. Moving a key to the cloud for 24/7 monitoring is a separate opt-in for each provider. The review screen shows how much each key can do: read-only billing keys get a calm recommendation, and keys that can manage the organization (Anthropic's admin key, for example) get a clear warning.
- **Pricing.** Free: readings sync, history, and alerts across Macs. Paid: cloud-held keys with always-on monitoring.

## In plain language

Someone connects Anthropic, Google, and Twilio in the menu bar app, sets a $50 daily alert, and ticks off half the caps audit. Months later they want alerts while the laptop is closed, so they create a Kill Cord Cloud account.

What they should get:

- **Keys stay put unless they say otherwise.** A new account syncs readings only (free): spend amounts and times go up so every Mac shows the same numbers, history builds up, and alerts reach all of them. No key moves.
- **No re-pasting when they want more.** For always-on monitoring (paid), the app already has the keys and offers to hand them over.
- **One provider at a time.** Each key has its own switch, and every switch starts off. Moving the Anthropic key says nothing about the Twilio key.
- **They see what the cloud will do with each key before it moves.** For example: "Reads your Anthropic cost report every 15 minutes, day and night. Never changes a setting."
- **Their settings come along on their own.** Thresholds, caps audit checkmarks, and which alerts already went out today aren't secrets, so they move when the account is created, and the review screen lists them.
- **Honest about the trade.** With readings only, the cloud knows only what a Mac told it, so there's still no coverage while every Mac sleeps. The review screen says so next to the switches.
- **They know what each key can do.** A read-only billing key (Cloudflare's Billing Read token, a Google service account limited to the billing export) gets a calm "this key can only read billing". A key that can manage the organization (Anthropic, Twilio, Neon, and Vercel) gets a clear warning before its switch.
- **A way back.** Stopping cloud monitoring for a provider deletes that key from the cloud right away. Leaving Kill Cord Cloud deletes everything there. The copy on the Mac stays and the app keeps working locally.

What has to stay true: until someone creates an account, every current promise holds word for word ("keys never leave your Mac except to the provider", "no account", "no telemetry"). When they do, the copy changes in the same release, before anyone can sign in.

## The flow

1. **Settings > General.** The "Always-on monitoring (coming later)" line becomes a "Kill Cord Cloud" section with one button: **Create a Kill Cord Cloud account** (and "Sign in" for a second Mac).
2. **Sign in.** The app opens the sign-in page in a system web sheet (`ASWebAuthenticationSession`). Sign in with Apple or an emailed link. The page returns a device token, which the app saves in the Keychain under its own service (`app.killcord.KillCord.cloud`), apart from provider keys. If the person belongs to more than one workspace, they pick which one this Mac's setup goes to.
3. **Review.** One screen, one row per connected provider:
   - the provider and the saved key's hint ("Ending in 0001", or the service account email for Google);
   - how much the key can do, from `ProviderID.keyPower`: `readOnly` shows a calm recommendation ("This key can only read billing. Good to move."), `readOnlyIfChosen` (OpenAI) asks them to confirm they picked the read-only option, and `canManage` shows a clear warning with the provider's `keyPowerWarning` text, for example that Anthropic's admin key can also manage members and API keys;
   - what the cloud will do with it, in one sentence, from the provider's lag and minimum refresh interval;
   - a switch, **Move this key to Kill Cord Cloud** (paid, always-on), off by default. On a free account it shows the upgrade;
   - for each switch turned on, a second, smaller choice: **Also keep it on this Mac** (on by default).

   Above the rows, a line says what happens with every switch off, the default: "Keys stay on this Mac. Kill Cord sends spend readings so your other Macs, history, and alerts stay in step. Nothing is watched while all your Macs sleep." Below them, "Coming with you" lists the non-secret settings that will copy over (thresholds, caps audit marks, alerts already sent this period).
4. **Sync and upload.** Settings and readings start syncing as soon as the account exists. For each switch that's on, the app reads that Keychain item at that moment, sends it over TLS, and the cloud checks it with the provider (the same `validate` call the app uses) before it stores anything. A rejected key shows the same inline message Settings would, and the other providers still go. The app records a provider as cloud-monitored only after the cloud confirms it.
5. **After.** The Settings sidebar and the panel show a small "Always on" mark on cloud-monitored providers and "Synced" on the rest. The General section shows the account, the workspace, and **Leave Kill Cord Cloud**.

## What moves, and when

| What | Where it lives today | Moves | Notes |
|---|---|---|---|
| Connection id and created date | Preferences, `connections` (new in #18) | Automatically | Becomes the cloud connection's id, so later calls name it without the key. |
| Alert thresholds | Preferences, `thresholds` | Automatically | Listed on the review screen. Copied as decimal strings. |
| Caps audit marks (done, doesn't apply, and when) | Preferences, `capAudit` | Automatically | The cloud doesn't re-ask questions the person already answered. |
| Alerts already sent this period | Preferences, `firedAlerts` | Automatically | Stops a second "you passed $50 today" from the cloud on the day of the move. |
| Cap verification readings | Preferences, inside `capAudit` | No | The cloud checks again with its own reads. |
| Spend readings | `~/Library/Application Support/Kill Cord/spend.json` (the last one only) | Automatically, as `SpendReading`, from then on | The readings-only sync, free. History starts on the day of the account: Kill Cord keeps no history before that, so there's none to carry. |
| Refresh interval, menu bar period, launch at login | Preferences | No | Settings for this Mac. The cloud's schedule follows each provider's minimum interval and the plan. |
| A provider's key and its other fields (account id, team id, export table) | Keychain, one item per provider | **Only when that provider's switch is on** | Non-secret fields go with their key, because together they identify the person's account at the provider. |

`LocalAccountSnapshot.make` (KillCordCore) produces exactly the "Automatically" rows plus a reference to each Keychain item. It never holds a key or a field value.

## Security model

- **Readings only by default, keys only by consent.** The default sync posts `SpendReading` values: amounts, usage, and times, built from a snapshot that never contains a key. Moving a key is a separate, explicit per-provider action, and it's the only path that gives overnight coverage. The app says so where the choice is made. Free accounts never hold a key.
- **In transit:** TLS 1.2 or later to one API host, through the app's existing ephemeral `URLSession`. The device token goes in an `Authorization` header and never in a URL.
- **At rest: envelope encryption.** Each stored credential is encrypted with its own data key (AES-256-GCM). The data key is wrapped by a KMS key for the account, with the account id and connection id as encryption context, so a wrapped key copied to another row or account won't decrypt. Plaintext keys live only in the polling worker's memory for the length of one provider request.
- **Least privilege.** Only the polling worker can decrypt. The API that receives uploads can only encrypt. Nobody at Kill Cord has a path to decrypt, and support tools see hints ("Ending in 0001"), never values. The cloud never changes a provider setting, the same rule as the app, and uses the same read-only calls.
- **Never logged.** Credentials are a redacted type on the server, as `ProviderCredentials` is in the app, and error text comes from fixed strings. The app's `SecretSafetyTests` move over as server tests: hostile responses that echo the key must not leak it into errors or logs.
- **No way back down.** The cloud never returns a key to any client, including the Mac that sent it. That makes it a write-only vault: a stolen device token can read spend, not keys. It's also why "Also keep it on this Mac" defaults on.
- **Delete on disconnect.** Stopping cloud monitoring for a provider deletes the ciphertext and its wrapped data key at once. Leaving Kill Cord Cloud deletes every credential and schedules the account's KMS key for deletion, so any backup copy becomes unreadable once the key is gone.
- **Visible activity.** The person can see every cloud read of their providers: when, which provider, and the result.

## Copy that changes on the day the cloud ships

Same release as the feature, never before. Each line keeps the free-app promise and adds the opt-in:

- `README.md` (the intro, the "Keeps keys in the Keychain" bullet, and the privacy section): "The free app has no account. If you choose Kill Cord Cloud, only the keys you pick go to it, encrypted, and you can take them back any time."
- `site/src/pages/index.html` (hero meta, the privacy cards, the cost FAQ) and `site/src/pages.json` descriptions: "Free with no account" stays true for the app, and a cloud line is added beside it.
- `site/src/pages/privacy/index.html`: the "No telemetry · No account" badge, and the "What goes over the network" section, which currently ends "no server of ours in between", gain a Kill Cord Cloud section: what it stores, the encryption, deletion, and the readings-only option.
- `KillCord/Settings/GeneralSettingsView.swift:71`: "Kill Cord goes online only to read your providers' billing APIs and to check for updates. No telemetry, no account." becomes "...and, if you've signed in, Kill Cord Cloud." The "(coming later)" line goes.
- `CLAUDE.md` rules "Network" and "Out of v1", and the "Free keys stay in the macOS Keychain and never leave the Mac" line in `docs/product/spec.md`, which already allows an explicit opt-in.

No telemetry still holds: the cloud gets readings and keys the person chose to send, never usage analytics.

## Disconnect and rollback

- **One provider:** "Stop cloud monitoring" deletes the key in the cloud. If the Mac kept its copy, nothing else changes locally. If it didn't, the provider shows "Not connected" on this Mac and the person pastes a key to watch it locally again. The cloud won't send it back.
- **Whole account:** "Leave Kill Cord Cloud" deletes cloud keys, readings, and settings copies, signs out every Mac, and puts each Mac back to local mode with whatever it kept. Leaving never deletes anything on the Mac.
- **Interrupted upload:** each provider uploads on its own and counts only once the cloud confirms, so a dropped connection leaves some providers moved and the rest local, and the review screen can be run again.
- **Older app versions:** the local data version stamp (`localDataVersion`) and the snapshot's `schemaVersion` let a newer app know what it's reading. An older app ignores preferences it doesn't know.

## More than one Mac

- Each Mac signs in on its own and shows up as a device under the account.
- Connection ids are per Mac (two Macs saving the same Anthropic key get two ids), so the cloud matches connections by the provider's own account identity (Anthropic or OpenAI organization, Cloudflare account id, Twilio account SID, Neon org id, Google billing export table) and says "Anthropic is already watched from another Mac" instead of storing a second copy.
- Once signed in, the cloud copy of thresholds and alert state is the one that counts, so every Mac shows the same limits and an alert fires once, not once per Mac.
- A second Mac doesn't need keys at all: it can show cloud readings for providers it never connected.

## Accounts and workspaces

Flexible accounts from day one. A cloud workspace (an organization) holds many members and many Macs, and a person can belong to many workspaces (their own, a client's, a company's):

- Users join workspaces through memberships with a role: owner, admin (can add and remove keys), or viewer (sees spend and alerts, never key hints).
- A workspace owns its connections, thresholds, alert routes, and devices. Everyone gets a personal workspace at sign-up.
- The review screen asks which workspace the Mac's setup goes to, and each provider can go to a different one.
- Removing a member signs out their devices for that workspace. Keys they moved stay with the workspace, since the workspace owns them, and the owner sees who added each one.
- Web side on the default stack: Better Auth with the organization plugin.

## Technical: what's stored today (audit)

From `development` at 4c07322, Kill Cord 0.1.1.

**Keychain** (`Packages/KillCordCore/Sources/KillCordCore/KeychainSecretStore.swift`)
- Generic passwords, service `app.killcord.KillCord.providers` (`Brand.swift:10`), account = provider id (`Credentials.swift:119`, `:130`), label "Kill Cord: Anthropic" (`KeychainSecretStore.swift:39`).
- The query sets only class, service, and account (`KeychainSecretStore.swift:15-21`). No `kSecAttrAccessible`, `kSecAttrSynchronizable`, access group, access control, or `kSecUseDataProtectionKeychain`. So items are in the file-based login keychain with its defaults: readable while the login keychain is unlocked, not synced to iCloud, and trusted for the app that created them.
- Payload: a JSON object of field id to value, every field of the provider including non-secret ones, with no version (`Credentials.swift:120`, `:124-131`). Field ids per provider (`Provider.swift:125-233`): Anthropic and OpenAI `apiKey`; Google `serviceAccountJSON` (the whole key file), `exportTable`, optional `billingAccountID`; Vercel `token`, optional `teamID`; Cloudflare `token`, `accountID`; Twilio `accountSID`, optional `apiKeySID`, `secret` (key secret or Auth Token); Neon `apiKey`, `orgID`; Supabase none.
- `CredentialStore.connected()` decides what's connected by which items exist (`Credentials.swift:138-140`).

**Preferences** (UserDefaults, `KillCord/App/Preferences.swift`)
- `refreshInterval`, `menuBarPeriod`, `appliedLaunchAtLoginDefault`, and JSON blobs `thresholds` (`SpendThresholds`, `ThresholdPlanner.swift:5-25`), `firedAlerts` (`ThresholdPlanner.swift:31-38`), `capAudit` (`CapsCatalog.swift:253-263`: marks and cap verifications). "Remove all local data" clears `Preferences.allKeys`.

**Files:** `~/Library/Application Support/Kill Cord/spend.json`, the last `ProviderState` per connected provider (`Preferences.swift`, `SpendCache`; `Freshness.swift:5`). No history beyond that. In-memory only: in-flight requests, scheduler state, last cap check times, which are all safe to lose.

**What would have blocked or complicated a migration**

1. **No stable id per connection.** A connection was only "the item named `openai`". Nothing could refer to it without the key, and the cloud couldn't tell a re-pasted key from a new connection. *Fixed in #18.*
2. **Nothing was versioned.** Not the preferences, the Keychain payload, or `spend.json`. *Fixed in #18 for preferences (version stamp) and the export (schema version); the Keychain payload stays as it is and a test now pins its field ids.*
3. **Saved shapes are Swift's defaults, hard to read from anything else.** `SpendThresholds.perProvider` is a dictionary with enum keys, which encodes as an alternating array. Cap marks are enums with associated values. Dates are seconds since 2001, and amounts are JSON numbers, which other languages read as floating point. *Fixed in #18: the snapshot uses plain strings, ISO 8601 dates, and decimal strings, and leaves the stored shapes alone.*
4. **One connection per provider.** The account name is the provider id, so two OpenAI organizations can't both be connected. That's fine for v1, but a workspace that manages clients will want it. *Later:* new items use `provider:uuid` as the account and the existing `provider` item stays readable, with no rewrite.
5. **Unreadable data looks like no data.** `Preferences.load` and `CredentialStore.load` return nil on a decode failure, so "couldn't read" and "nothing saved" look the same. *Later:* a migration must tell those apart before it says "nothing to move".
6. **File-based keychain trusted for the app.** Fine for the app reading its own items at upload time. A future CLI or helper would get a Keychain prompt, so the upload belongs in the app. Not synced to iCloud, which is right: Macs share through the cloud, not iCloud Keychain.

## Technical: groundwork shipped in #18

All local, no network, no new UI:

- `ConnectionRegistry` and `ConnectionRecord` (KillCordCore): a UUID and created date per connected provider, rebuilt from the Keychain on launch, connect, and disconnect. Existing ids are kept, a replaced key keeps its id, and a disconnect drops the record. Keys saved by 0.1.1 get an id on the next launch, and their Keychain items aren't touched. The records are kept in preferences (`connections`), not as Keychain attributes, so no existing item is ever rewritten, and losing the preferences only means new ids.
- `localDataVersion` preference, stamped to 1. 0 or missing means saved by 0.1.1 or earlier.
- `SpendReading` (KillCordCore, follow-up PR): the readings-only payload, built from a `SpendSnapshot` and a connection id, with decimal strings and ISO 8601 dates. It never sees a key.
- `ProviderID.keyPower` (KillCordCore, follow-up PR): `readOnly` (Cloudflare, Google), `readOnlyIfChosen` (OpenAI), `canManage` (Anthropic, Vercel, Twilio, Neon), `noKey` (Supabase), for the review screen's tone. A test checks that every `canManage` key has warning text.
- `LocalAccountSnapshot.make(credentials:registry:state:now:)` (KillCordCore): the one function a migration calls, a versioned JSON-ready value with settings, thresholds as decimal strings, cap marks, sent alerts, and per connection its id, created date, and Keychain reference (service, account, saved field ids, which are secret). It reads the credential store only to see which fields are saved.
- Tests with fake keys only: readings carry amounts as text and the right connection id, and skip providers with no record or no reading. And the snapshot contains no secret and no field value, references every item correctly, round-trips, leaves out records with no item, and leaves the items byte-for-byte unchanged. Registry tests cover adoption, stable ids, drop, and re-connect. A test pins every provider's credential field ids and the Keychain service name.
- README and privacy page now mention the per-connection id.

## Technical: what the cloud build will need later

- `CloudClient` protocol in KillCordCore with a mock, like `HTTPClient`, plus a `cloud` state per connection id (`local`, `cloud`, `cloud+local`) in preferences.
- Endpoints: `POST /v1/devices` (sign-in exchange), `PUT /v1/settings` (the snapshot minus connections), `PUT /v1/connections/{id}` (provider, fields, sent once over TLS), `DELETE /v1/connections/{id}`, `POST /v1/readings` (readings-only), `DELETE /v1/account`.
- Polling worker: KillCordCore already builds and tests on Linux, so the server can run the same adapters, Redactor, freshness, and threshold logic, rather than a second copy in another language that could drift.
- Web and account side: Next.js, Prisma Postgres, Better Auth with organizations, Stripe for the plan.

## Decisions

Decided by Corey on November 16, 2026:

1. **Hybrid key model.** Readings only by default; moving a key is a per-provider opt-in, with the key's power shown on the review screen. See "Decided" at the top.
2. **Pricing.** Free: readings sync, history, and alerts across Macs. Paid: cloud-held keys with always-on monitoring.

Still open (recommendations):

3. **Keep the Mac's copy after moving.** Recommendation: yes by default, and the cloud never sends keys back down.
4. **KMS key per account or one key with per-account encryption context.** Only paid accounts hold keys, so only they need key encryption at all. Recommendation: one KMS key per paid account (about $1 a month each on AWS KMS), which makes leaving a clean crypto-shred.
5. **Server language for the worker.** Swift on Linux reusing KillCordCore (recommended) or TypeScript ports of the adapters.
6. **Sign-in methods.** Sign in with Apple and an emailed link (recommended), or email and password.
7. **Trial.** Whether paid always-on monitoring starts with a trial, and how long.
