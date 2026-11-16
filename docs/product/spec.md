# Kill Cord: product opportunity analysis

> Product spec, revised November 15, 2026. Originally drafted under the working name Spend Guard.

Updated November 15, 2026 (Pacific Time) after the product shape was chosen: a source-available macOS menu bar app in the existing Mac app family, with a paid always-on cloud monitor later. Verdict: go on the free local app; go-if on the paid cloud tier.

## Contents

- [Verdict](#verdict)
- [The brief](#the-brief)
- [The job and the field](#the-job-and-the-field)
- [Better-model test](#better-model-test)
- [Defensibility](#defensibility)
- [Sharpest wedge, pricing, and v1 scope](#sharpest-wedge-pricing-and-v1-scope)
- [Critical journeys](#critical-journeys)
- [Trust and credentials](#trust-and-credentials)
- [Platform, stack, and outcomes](#platform-stack-and-outcomes)
- [Biggest risks](#biggest-risks)
- [Build units and proof](#build-units-and-proof)
- [Cheap validation plan](#cheap-validation-plan)
- [Next step](#next-step)
- [Sources](#sources)

## Verdict

> **Go on the free Mac app. Go-if on the paid always-on cloud.**
>
> The product shape has been chosen. v1 is a source-available macOS menu bar app: today and month spend at a glance, keys in the Keychain, local polling while the Mac is awake, local notifications, and a guided native-caps audit. The paid upgrade is a 24/7 cloud monitor and alerts for when the Mac is asleep. Pre-authorized auto-stop stays later, not in the first paid ship.

This replaces the earlier web-SaaS kill-switch brief. That shape fought Costbrake on coverage and asked for write credentials on day one. The Mac app fits the existing Mac app family (Fuel Gauge, Spare, Midnight Oil, and the others), leads with local-first trust, and still has a clean paid reason: watching spend while the laptop is closed. Do not build the cloud tier, or auto-stop, until the local app is dogfooded on Anthropic and Google and the audience asks for always-on.

## The brief

- **Mode:** Spec, revised November 15, 2026 (Pacific Time), after the product shape was decided. No app repo yet.
- **Working name:** Kill Cord
- **Platform:** macOS menu bar app (decided). Paid cloud worker is an upgrade, not the v1 surface.
- **Who uses it:** The person at the Mac. Free tier is single-user and local. Paid is the same person, always-on. Not a multi-team SaaS in v1.
- **Profile:** Local macOS utility, with an optional hosted monitor later.
- **License (proposed):** FSL-1.1-MIT, to match Fuel Gauge, Midnight Oil, Green Room, Wi-Fi or ISP, and Disk Forecast.
- **Hard-to-reverse picks:** Free keys stay in the macOS Keychain and never leave the Mac. Paid cloud holds only scoped read-only billing credentials, and only after an explicit opt-in.

Audience: founders and indie devs on a Mac who juggle usage-based APIs, especially people already in the existing Mac app family's audience. Anthropic and Google are the two bills that most often surprise this audience; many also use OpenAI, Vercel, Cloudflare, Twilio, Neon, and Supabase.

The job: see today and this month's spend without opening five billing consoles, get the provider's own caps actually turned on, and optionally get an alert if spend runs away while the Mac is asleep. Today's workarounds are those consoles, native caps that are easy to leave unset, cloud dashboards that require handing over keys, and Fuel Gauge, which already forecasts Claude Code, Codex, Grok Bot, and Cursor plan limits, not API dollar spend.

Useful outcome for free: glanceable spend, an honest last-checked time, and a cap audit that is done or clearly unfinished. Useful outcome for paid: an alert arrives even when the laptop is closed. "Done" is a bounded surprise, not a prettier chart. Auto-stop is out of the first paid ship.

## The job and the field

Kill Cord is not trying to fill the old "auto-stop plus 35 providers" quadrant. Free lives on the Mac and is honest that it stops polling when the machine sleeps. Paid is always-on alerts, like Costbrake or Vantage, but as an upgrade from an app that already earned trust locally. Native caps remain the hard stop.

### Landscape matrix

A 2x2 with these axes:

- **x axis:** Local, only while awake (0) to Always-on (1)
- **y axis:** Alerts or glance (0) to Hard stop (1)

Quadrants: Local glance (bottom left), Always-on alerts (bottom right), Local stop (top left), Always-on hard stop (top right).

| Product | x | y | Quadrant |
| --- | ---: | ---: | --- |
| Kill Cord free | 0.18 | 0.28 | Local glance |
| Fuel Gauge | 0.16 | 0.22 | Local glance |
| Kill Cord paid | 0.72 | 0.32 | Always-on alerts |
| Costbrake | 0.78 | 0.48 | Always-on alerts |
| Vantage | 0.74 | 0.22 | Always-on alerts |
| Billfuse | 0.76 | 0.62 | Always-on hard stop |
| Native caps | 0.88 | 0.86 | Always-on hard stop |
| LiteLLM | 0.70 | 0.84 | Always-on hard stop |

### Comparison

| Product | Fit vs this shape | Price | Main gap |
| --- | --- | ---: | --- |
| Fuel Gauge | Sibling menu bar app. Forecasts Claude Code, Codex, Grok Bot, and Cursor plan limits. Usage stays on the Mac. | Free | Plan-limit fuel, not API dollar spend or native billing caps. Position Kill Cord as the bill cousin, not a replacement. |
| Costbrake | Closest always-on inbox: billing APIs, 35 providers, alerts, confirm-to-brake on 18 | Free for 2 accounts; Pro $12/mo; Team $39/mo | Keys live on their servers from the start. No local-first Mac app. Brakes need a human click. |
| Vantage | Established cloud plus AI FinOps, including Anthropic, OpenAI, Cloudflare, Vercel, Twilio | Free to $2,500 tracked spend; Pro $30/mo | Observational, no Mac app, no native-caps wizard. The free tier is the price pressure on a paid monitor. |
| Billfuse | LLM billing APIs and optional automatic pause | Unknown | No Mac client. LLM-only. Pause is later for Kill Cord too. |
| Native caps | The actual hard stops inside each console | Included by the provider | Easy to leave unset. The free app's job is to get them turned on. |

Official pages: https://fuelgauge.app, https://costbrake.com, https://www.vantage.sh/pricing, https://billfuse.dev. Thin 2025 and 2026 indie dashboards (Spendwall, TryTokka, BillCurfew, and others) still crowd the cloud-inbox category. That is another reason to enter as a Mac app in a known family, not as the 36th billing dashboard.

## Better-model test

If the next model is much better at the intelligence part, this product gets more useful, not less. Better models and more autonomous agents spend more API dollars, more often, including overnight. The product's contribution is not a prompt. It is local Keychain handling, per-provider billing adapters, a cap audit, and, for paid users, a reliable always-on watcher and alert path. The thing that would make the free app less necessary is every provider shipping a glanceable, trustworthy cap that founders actually enable. The thing that would make the paid tier less necessary is a Mac that can poll while fully asleep, or native caps so complete that overnight alerts feel redundant.

## Defensibility

Code is still cheap. The wedge is trust and distribution, not a long integrations list. Scores below are judgment scores from the defensibility lens, not measured market data.

### The family this should join

Checked on the maintainer's public GitHub (https://github.com/coreyhaines31), November 15, 2026 (Pacific Time). The recent menu bar family splits into MIT apps that stay fully local (Spare, OnHand, Coat Check, and the PanelKit UI kit) and FSL-1.1-MIT source-available apps (Fuel Gauge, Midnight Oil, Green Room, Wi-Fi or ISP, Disk Forecast). Shared conventions: macOS 14 or later, signed and notarized GitHub Release DMGs, Homebrew casks on the family Homebrew tap (https://github.com/coreyhaines31/homebrew-tap), Sparkle updates, often a CLI and an optional MCP, and a privacy line that data stays on the Mac. Kill Cord should follow those conventions. FSL-1.1-MIT is the better license match than Spare's MIT, because a paid cloud upgrade is planned, the same way Fuel Gauge is source-available rather than MIT.

| App | License | Trust line |
| --- | --- | --- |
| Spare | MIT | No account, no subscription, nothing leaves your Mac. |
| OnHand | MIT | History stays on your Mac. |
| Fuel Gauge | FSL-1.1-MIT | Usage never leaves your Mac (Cursor is an explicit exception). |
| Midnight Oil, Green Room, Wi-Fi or ISP, Disk Forecast | FSL-1.1-MIT | Free, source-available menu bar apps. |
| Kill Cord (proposed) | FSL-1.1-MIT | Free: keys in Keychain, never leave. Paid: scoped read-only keys, server-side, only after opt-in. |

### Attacks that apply

| Attack | Risk | Evidence |
| --- | --- | --- |
| The customer builds it | Medium | A script can poll two billing APIs. It will not look like the family, store keys in Keychain, or walk someone through native caps. |
| Competitors reach parity in months | Medium | A cloud inbox is easy to copy. A trusted local Mac app in this family is harder to copy than another dashboard. Costbrake could still ship a menubar client. |
| The platform ships your feature | High for hard-stop, lower for glance | Native caps are the stop. The free app complements them with a cross-provider glance and an audit. Cloudflare Spend Management launched November 13, 2026 (Pacific Time). |
| Open source plus an agent to deploy it | Designed around | The app itself will be source-available. FSL-1.1-MIT blocks a competing commercial substitute and becomes MIT after two years, same as Fuel Gauge. |
| The human user is replaced | Medium | Agents already spend overnight. A later CLI, in the family pattern, lets an agent read status. It should not arm cloud credentials or auto-stop on its own. |
| The model absorbs it | Low | Value is not "our prompt beats the model." |

### Moats v1 can build toward

| Moat | Now | Decision that starts it |
| --- | ---: | --- |
| Buyers know and trust you | 6 | Ship in the existing Mac app family, keep free keys on-device, and tell the Fuel Gauge audience this is the API-bill cousin. This is the v1 moat. |
| Hard to keep running | 4 | Provider adapters drift. The paid worker, alerts, and notarized releases are ongoing ops. That pain is real. |
| Allowed to act | 2 | v1 acts by getting native caps turned on. Paid acts with 24/7 alerts. Auto-stop stays later. |
| System of record | 2 | Local spend history and cap-audit state on the Mac. Paid adds an alert and check history in the cloud. |
| Nobody checks your work | 0 | Do not claim this. Show freshness and provider lag, especially for Google Cloud. |
| Someone official said yes | 0 | Notarization is the Mac release bar. SOC 2 is only relevant if the paid cloud holds many customers' keys. |
| Everyone's already in it | 1 | Out of reach. This is a single-player Mac app in v1. |
| Every customer makes it smarter | 1 | Do not pool spend data in v1. Free stays local. |

v1 builds toward "buyers know and trust you," with local-first and source-available as the proof, and toward the ops of adapters and releases. "Allowed to act" gets a first step through the caps wizard, not a kill switch.

## Sharpest wedge, pricing, and v1 scope

Sharpest wedge: a free, source-available menu bar glance at API spend, with keys that never leave the Mac, plus a guided native-caps audit. The paid upgrade is always-on monitoring and alerts when the Mac is asleep. Start providers with Anthropic and Google Cloud or Gemini, the two bills that most often surprise this audience, then OpenAI, Vercel, and Cloudflare in the cap audit and spend adapters.

### Flow

1. **Install** (start): DMG or Homebrew
2. **Keychain:** keys stay on the Mac
3. **Glance:** today and month
4. **Cap audit** (decision): guided native caps
5. **Paid cloud** (reached via opt-in): read-only, 24/7 alerts
6. **Auto-stop** (end, later, dashed edge): later, not v1 paid

Pricing is a hypothesis, not a measured willingness-to-pay: free forever for the local app, in line with the family; paid always-on around $8 to $12 a month, in the same band as Costbrake Pro at $12 a month, justified by overnight coverage rather than by a bigger dashboard. Vantage is free up to $2,500 of tracked spend, so some founders will not pay for a cloud inbox alone. A yearly option can wait. Do not price as a percentage of spend.

### In for v1 (free Mac app)

- Menu bar today and month spend, last-checked time, local notifications
- Keys in macOS Keychain, never uploaded
- Local polling only while the Mac is awake, with an honest stale state after sleep
- Guided native-caps audit: Anthropic spend limits and a non-default workspace, OpenAI enforced hard limits, Gemini or AI Studio plus Cloud Billing spend caps, Vercel pause-on-budget, Cloudflare Workers limits
- Anthropic and Google or Gemini adapters first, then OpenAI, Vercel, and Cloudflare
- FSL-1.1-MIT, notarized DMG, Homebrew cask on the family tap (https://github.com/coreyhaines31/homebrew-tap), Sparkle updates

### Out of v1

- Always-on cloud in the first public build
- Auto-stop or any write credential, including later paid, until the local loop is trusted
- A 35-provider Costbrake clone or a web dashboard as the main surface
- Merging with Fuel Gauge, or with the broader cybersecurity SaaS, on day one
- Accounts, orgs, or analytics on the free app
- A promised maximum invoice

Acceptance for the free app: on the maintainer's Mac, Anthropic and Gemini or Google Cloud spend appear in the menu bar, match the provider within documented lag, keys are found only in Keychain, a cap audit shows what is missing and links to the right console page, and after the Mac sleeps the UI says when it last checked instead of implying live coverage. Acceptance for paid, when it ships: alerts fire while the Mac is off, on a scoped read-only credential the user explicitly uploaded, with no Keychain secret copied silently.

## Critical journeys

Design direction is a proposal. Follow the family's menu bar patterns (no Dock icon by default, panel from MenuBarExtra). PanelKit exists for a Brushed popover style, but only use it if it fits this app. Errors and irreversible consequences stay inline, never only in a tooltip.

### First use (free)

Install from a notarized DMG or Homebrew, no account. Click the menu bar icon, add a read-only billing credential, see it stored in Keychain, and get today and month spend plus a last-checked time. Then run the cap audit and open each provider's settings page to turn missing caps on. Primary actions: Connect, then Review caps, then Set this cap.

### Return visit (free)

Click the icon, glance totals and per-provider spend, and see whether the last poll is fresh or stale after sleep. The primary action is inspect, not reconfigure.

### Paid upgrade, later

From the panel, choose always-on monitoring. The app must explain, inline, that a scoped read-only billing credential will be stored on the server, that Keychain keys will not be uploaded unless the user confirms that destination, and that auto-stop is not part of this upgrade. Then the user creates an account, grants the cloud credential, picks Slack, SMS, email, or push, and gets a test alert.

### States to design

| State | UI | Guidance |
| --- | --- | --- |
| Empty | No providers yet, Connect as the primary action | Say the key stays in Keychain and never leaves the Mac. |
| Invalid key | Inline error, input kept | Do not log or display the secret. |
| Denied scope | Explain the missing permission | Ask for the narrowest billing or usage scope, not a full admin key, when the provider offers one. |
| Polling | Last-checked time, freshness by provider | Show lag honestly, especially for Google Cloud. |
| Mac slept | Stale, last checked at this time | Never imply overnight coverage on the free app. Offer paid always-on as an option, not a scare. |
| Notification denied | Inline, how to enable in System Settings | A tooltip on a disabled control is not enough. |
| Cap missing | Audit row with Open this setting | The app does not flip the cap itself in v1. It guides. |
| Cap set | Clear done state in the audit | Re-check on a later launch, because caps can be removed. |
| Offline | Cached last spend, marked not live | No silent cloud upload. |
| Paid opt-in | Preview what will be stored server-side, confirm | Separate read-only credential. No write keys. |
| Paid alert failure | Delivery failed, retry and status | Do not claim the user was notified if the send failed. |

Consequential actions that need preview or confirm: storing a key, opting into the paid cloud, granting a server-side credential, and deleting credentials or the app's local data. Uninstall should say how to remove Keychain items and local history, in the family pattern.

## Trust and credentials

The product has a trust split, and that split is the product. Free and paid are different contracts. Start the threat model with what the app ingests: billing keys, and later, for paid, a copy of a read-only key that will live on a server. Route a formal threat model and secrets review to a security reviewer before the paid tier is designed in detail, covering threat modeling, a secrets audit, and, for the cloud API, API, OWASP, and IAM audits.

### Free tier: keys never leave the Mac

1. Store provider secrets only in the macOS Keychain, not in app support files, logs, traces, or screenshots of feedback.
2. The Mac calls provider billing APIs itself. Checking for app updates is the other network path, same as Spare and Fuel Gauge.
3. Never silently copy a Keychain secret to a server, a sync service, or a support bundle.
4. Be honest when a provider has no read-only billing key. Earlier research found Anthropic's Admin API has no read-only option, so even a "usage" key can be powerful. The UI should say that.
5. A key pasted into an agent chat is leaked and should be rotated. Do not ask people to paste keys into chat to set the app up.

### Paid tier: scoped read-only, server-side, opt-in

1. Always-on requires a credential the server can use while the Mac sleeps. That is a new trust event, not a hidden upload of the Keychain item.
2. Hold only a scoped read-only billing or usage credential. No write keys, no inference keys, no auto-stop in this upgrade.
3. Show, inline, what will be stored, where, who can access it, how to revoke it, and that spend metadata will be processed on the server to send alerts.
4. Encrypt at rest, keep secrets out of logs and traces, isolate tenants if more than one account exists, and make revoke and purge real, not only a soft delete.
5. Do not promise a maximum invoice. Google Cloud billing export can run hours behind even when the watcher is always on.

### Outcomes

| Outcome | Free app | Paid cloud, when it ships |
| --- | --- | --- |
| O1 Users, orgs, roles | Justified N/A: single-user, local. | Single-player account first. No team roles until there is a real shared-bill case. |
| O2 Feedback to the builder | Applies: in-app text, optional screenshot with consent and redaction. Warn if a capture could include a key. | Same path, plus a support identity that cannot read stored credentials by default. |
| O3 Security that fits the risk | Applies: Keychain, least privilege, no secret leakage, notarized releases. | Applies, critical: server-side secret handling is a launch blocker for this tier. The security review belongs here. |
| O4 Privacy-aware analytics | Justified N/A if the free app stays in the family pattern: no telemetry, or only an update check. | Minimal and decided first: alert delivered or failed, never key material or raw billing line items in analytics. |
| O5 Agent access | Revisit after v1, in the family pattern: a read-only status CLI. Not required to ship the panel. | An agent must not grant cloud credentials or arm auto-stop. Drafting is not approval. |

## Platform, stack, and outcomes

Profile: local macOS utility. Stack for the app, from the Apple default and the family: Swift and SwiftUI, MenuBarExtra, Keychain, per-provider billing adapters, Sparkle for updates. Confirm minimum OS (family is macOS 14) and whether the first build is Apple silicon only, as Spare is, or Intel as well, as the Fuel Gauge readme does not restrict. Distribution: signed and notarized DMG, GitHub Releases, Homebrew cask on the family tap (https://github.com/coreyhaines31/homebrew-tap), a small site in the family style. XcodeGen and SwiftLint are what Fuel Gauge uses to build; match that unless there is a reason not to.

Paid cloud is an open stack choice, not decided here: a worker that polls billing APIs on a schedule, stores scoped credentials in a proper secret store, and sends Slack, SMS, email, or push. Stripe for the upgrade. This is a departure from a pure local profile, and only after the free app is real. Open choices also include the SMS and push providers.

Performance, baselines only until something exists: time to first spend reading, poll duration by provider, menu bar hitch, and, for paid, time from a threshold to a delivered alert. Measure freshness after wake from sleep. Do not add a cache of secrets or spend that bypasses Keychain or authorization.

## Biggest risks

1. **The Mac is asleep when the bill runs away.**
   - This is the free tier's honest limit and the reason for paid. The UI has to say last-checked time. If that state is fudged, the trust wedge dies.
2. **Provider lag and coverage, especially Google Cloud.**
   - Billing export can run hours behind even with a 24/7 worker. Adapters will break as APIs change. A long provider list makes that worse, so start with two.
3. **People confuse this with Fuel Gauge, or will not pay because Vantage and Costbrake exist.**
   - Position it as API dollar spend and cap setup, not plan-limit fuel. Paid has to be "works while your Mac sleeps," not "another dashboard." The $8 to $12 a month figure is only a hypothesis.
4. **The paid trust jump is too large.**
   - Some founders will use the free app and never upload a key. That is a fine outcome. Do not blur the boundary to raise conversion.
5. **Maintenance of adapters, notarization, Sparkle, and the Homebrew tap.**
   - The family already carries this cost. A paid tier that is late or flaky will feel worse than no paid tier.
6. **Auto-stop, if pulled forward too soon.**
   - False positives and write credentials are still existential. Keep it later.

## Build units and proof

Nothing is built, so launch readiness is unproven. If they proceed, these are the first units. Cheapest meaningful proof: unit tests for adapters and cap-audit rules, a Keychain integration test that secrets never hit the log, and a few end-to-end journeys on a real Mac, including wake-from-sleep staleness. Before calling the Mac app ready to ship: signed, notarized, and Gatekeeper-checked on a second Mac, in the family pattern. A backup of local data is not a restore proof until someone restores it.

| Unit | Acceptance | Rollback |
| --- | --- | --- |
| Menu bar shell | Installs, appears in the menu bar, no account required, quit and uninstall documented. | Unpublish the DMG and cask. |
| Keychain credential store | A key can be added, used, and deleted. It does not appear in logs, files, or a support export. | Instruct a Keychain delete; stop shipping the build. |
| Anthropic and Google or Gemini adapters | Spend matches the provider within documented lag, with last-checked time. | Disable that provider in the panel. |
| Wake and stale state | After sleep, the panel shows last checked, not live coverage. | Fix before any public claim of monitoring. |
| Native-caps audit | Each of the five provider flows names the missing cap and opens the right settings page. | Ship spend glance without the audit, rather than a wrong link. |
| Paid cloud (later) | A test alert arrives while the Mac is off, using only an explicitly granted read-only credential. | Feature-flag the upgrade off; revoke server secrets. |

Readiness for this scope: not assessed on every control, because there is no revision to exercise. Verdict if someone asked whether it is ready to launch: unproven. That is expected before the dogfood build. It is not a pass.

## Cheap validation plan

Status as of November 15, 2026 (Pacific Time). Validate the local app by using it, then launch it to the existing Mac app family's audience. Do not build the paid cloud first.

- [ ] Set the maintainer's native caps now, even before the app exists: Anthropic, Google or Gemini, OpenAI, Vercel, and Cloudflare, plus Twilio, Supabase, and Neon alerts where those exist.
  - Still the fastest protection. Status as of November 15, 2026 (Pacific Time).
- [ ] Dogfood a menu bar build on the maintainer's Anthropic and Google or Gemini accounts, with keys in Keychain only.
  - Prove glance, lag, sleep-stale, and the cap audit on the two bills that most often surprise this audience.
- [ ] Add OpenAI, Vercel, and Cloudflare to the cap audit, then to spend adapters if the first two adapters hold.
  - Do not start at 35 providers.
- [ ] Launch the free app to the existing Mac app family's audience, with a clear Fuel Gauge distinction.
  - Count installs, cap-audit completions, and unprompted asks for always-on. That last number decides the paid tier.

1. **Pass for the free app:** The maintainer would miss it if it were gone, spend numbers are trusted, and the cap audit has been used for real. Then ship to the audience.
2. **Pass for paid, later:** Enough unprompted asks for always-on, plus a design for scoped read-only server secrets that a security reviewer would stand behind. Then build the worker. The "enough" bar is a judgment call, not a measured market size.
3. **Fail:** If the local glance is less useful than the provider consoles, or if Fuel Gauge already covers the itch people thought this would scratch, stop before a cloud tier. Keep the native caps on either way.

## Next step

One action: start the local Mac app for Anthropic and Google or Gemini, and set the native caps today while that is built. The paid always-on monitor waits on a working dogfood and demand from the launch. If this later lives in a repo, the spec belongs at docs/product/spec.md, in the family style of the other menu bar apps.

## Sources

- [Fuel Gauge](https://fuelgauge.app) (fuelgauge.app)
- [Fuel Gauge source and FSL license](https://github.com/coreyhaines31/fuelgauge) (github.com)
- [Spare](https://spareformac.com) (spareformac.com)
- [Spare source, MIT](https://github.com/coreyhaines31/spare) (github.com)
- [Midnight Oil, FSL-1.1-MIT](https://github.com/coreyhaines31/midnightoil) (github.com)
- [OnHand](https://github.com/coreyhaines31/onhand) (github.com)
- [Green Room](https://github.com/coreyhaines31/greenroom) (github.com)
- [Wi-Fi or ISP](https://github.com/coreyhaines31/wifiorisp) (github.com)
- [Disk Forecast](https://github.com/coreyhaines31/diskforecast) (github.com)
- [PanelKit](https://github.com/coreyhaines31/panelkit) (github.com)
- [Costbrake](https://costbrake.com/) (costbrake.com)
- [Vantage pricing](https://www.vantage.sh/pricing) (vantage.sh)
- [OpenAI spend limits](https://developers.openai.com/api/docs/guides/spend-limits) (developers.openai.com)
- [Anthropic rate and spend limits](https://platform.claude.com/docs/en/api/rate-limits) (platform.claude.com)
- [Google Cloud spend cap budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps) (docs.cloud.google.com)
- [Gemini API billing and spend caps](https://aistudio.google.com/docs/billing) (aistudio.google.com)
- [Vercel Spend Management](https://vercel.com/docs/spend-management) (vercel.com)
- [Cloudflare Spend Management](https://developers.cloudflare.com/billing/manage/spend-management/) (developers.cloudflare.com)

## Status in this repo

v1 (the free local Mac app) is what this repository builds. The paid always-on monitor and auto-stop are out of scope for v1.
