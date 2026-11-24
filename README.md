<p align="center">
  <img src="KillCord/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" alt="Kill Cord icon">
</p>

<h1 align="center">Kill Cord</h1>

<p align="center">See today's and this month's API spend in your menu bar, and get each provider's own spend caps turned on. A free macOS menu bar app for Anthropic, Google Cloud and Gemini, OpenAI, Vercel, Cloudflare, Twilio, Neon, and Supabase, plus prepaid balances on OpenRouter, DataForSEO, Ahrefs, Firecrawl, treg, Monid, fal, ElevenLabs, xAI, DeepSeek, Tavily, Deepgram, Runway, SerpApi, Bright Data, ScrapeCreators, Stability AI, Kimi, Exa, ScrapingBee, Scrapfly, Kie.ai, and Bland AI.</p>

<p align="center">
  <a href="https://github.com/coreyhaines31/killcord/releases/latest">Download</a> ·
  <a href="#install">Install</a> ·
  <a href="#first-run">First run</a> ·
  <a href="#caps-audit">Caps audit</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="#uninstall">Uninstall</a>
</p>

---

Usage-billed APIs don't send a bill until it's too late to matter. An agent loop, a leaked key, or a forgotten batch job can run all night. Kill Cord puts today's and this month's spend for every provider in one glance, says honestly how fresh each number is, and walks you through turning on the caps each provider already offers, since those are what actually stop a runaway bill.

It's free, the source is on GitHub, and your keys stay in your Mac's Keychain. They never leave your Mac except to go to the provider they belong to.

## What it does

- **Shows spend in the menu bar.** Total spend today or this month next to a small plug. Click for each provider's today and month-to-date.
- **Is honest about freshness.** Every provider shows when it was last checked. Kill Cord checks only while your Mac is awake. After sleep, or offline, numbers say "Last checked 11:42p, not live" until the next check. It never implies it watched overnight.
- **Shows provider lag.** Some providers run behind. Google's billing export can be most of a day behind, and the panel says so.
- **Says what it can't see.** Neon reports usage, not dollars. Supabase has no billing API. Totals list what they leave out.
- **Walks you through native caps.** For each provider: the spend controls it offers, whether each is a hard stop or only an alert, and a button that opens the exact console page. Where an API can confirm a cap, Kill Cord checks it. Elsewhere it's your checkmark, and it asks you to look again after 30 days.
- **Shows prepaid balances.** For services you pay up front or that come with credits (OpenRouter, DataForSEO, Ahrefs, Firecrawl, treg, Monid, fal, ElevenLabs, xAI, DeepSeek, Tavily, Deepgram, Runway, SerpApi, Bright Data, ScrapeCreators, Stability AI, Kimi, Exa, ScrapingBee, Scrapfly, Kie.ai, Bland AI), what's left, in dollars, credits, or API units. A balance is what's left, not spend, so it never adds into your totals.
- **Takes any balance endpoint.** A custom connection reads a service Kill Cord doesn't know from an https address you enter and a path into its JSON. Kill Cord can't verify those numbers and says so.
- **Remembers plans with no API.** For services like Truelist or Gojiberry, enter the plan, price, and renewal date. Twelve AI services with no billing API (Replicate, Groq, Perplexity, Cohere, AssemblyAI, E2B, Cerebras, Jina AI, Twelve Labs, Unstructured, Voyage AI, and TypeSafe Jev) are presets: pick one and Kill Cord links its billing page and adds its own spend caps to the audit. It's marked "Not live: entered by you", stays out of your totals, and Kill Cord reminds you before it renews.
- **Alerts you.** Notifications at daily and monthly amounts you choose, per account, per provider, and in total, once per day or month. Low-balance alerts fire once when a balance drops to your amount, and again only after a top-up.
- **Keeps keys in the Keychain.** Not in files, preferences, logs, or exports. No account, no telemetry.

## Provider coverage

| Provider | Spend source | Key you need | Dollars? | Caps Kill Cord can confirm |
| --- | --- | --- | --- | --- |
| Anthropic | Admin API cost report | Service account or personal key not scoped to a workspace, or an Admin API key (`sk-ant-admin…`). Needs an organization, not an Individual Org | Yes, within about 5 minutes | None (no API for Console spend limits; your checkmark) |
| Google Cloud and Gemini | Cloud Billing export to BigQuery | Service account key with read access to the export | Yes, after one-time setup; hours behind | Spend cap budgets and budget alerts (Budget API, optional) |
| OpenAI | Organization costs | Admin API key (`sk-admin…`) | Yes | Organization hard limit |
| Vercel | Billing charges (FOCUS) | Access token | Yes, daily | None (no API for Spend Management) |
| Cloudflare | Billable usage (alpha, pay-as-you-go accounts) | API token with Billing Read | Yes, daily; billing period, not calendar month | Spend Management limits |
| Twilio | Usage records (total price) | API key or Auth Token | Yes | Usage triggers on total price |
| Neon | Consumption history | Organization API key | No: usage only (compute hours, storage, transfer) | Spending threshold |
| Supabase | None | Nothing to connect | No: no billing API | None (Spend Cap is your checkmark) |
| OpenRouter | Key limits and usage | API key (reads that key only) | Balance left on the key, plus the key's spend today and this month | None (per-key credit limit is your checkmark) |
| DataForSEO | Account data (free call) | API login and password | Balance left, in dollars | None |
| Ahrefs | Limits and usage (free call) | API key | Workspace API units left | None |
| Firecrawl | Team credit usage | API key | Credits left | None |
| treg | Team balance | Team or agent token | Balance left, in dollars | None |
| Monid | Wallet balance | API key | Balance left, in dollars | None (budgets are your checkmark) |
| fal | Account credits | API key with the BILLING preset | Balance left, in dollars | None (the balance is the cap) |
| ElevenLabs | Subscription credits | API key limited to User read | Credits left this period | None (key quotas are your checkmark) |
| xAI | Prepaid credits (Management API) | Management key and team ID | Balance left, in dollars | None (the invoiced billing limit is your checkmark) |
| DeepSeek | Account balance | API key | Balance left, in dollars or yuan | None (DeepSeek documents no cap) |
| Apify | Usage this cycle and the usage limit | API token | Yes, this usage cycle, plus what's left before the limit | Usage limit |
| Tavily | Plan credits this cycle | API key | Credits left of the plan | None (workspace and key limits are your checkmark) |
| Deepgram | Project balances | API key with the Admin role (plus the project ID if it sees several) | Balance left, in dollars | None (Deepgram documents no cap) |
| Runway | Organization credits | API key | Credits left, with a labeled dollar estimate at $0.01 a credit | None (autobilling off is your checkmark) |
| SerpApi | Account searches | Private API key | Searches left this month | None |
| Bright Data | Account balance | API key with the Finance permission level | Balance left, in dollars | None (zone limits are your checkmark) |
| ScrapeCreators | Account credits | API key | Credits left | None (the credits are the cap) |
| Stability AI | Account credits | API key | Credits left, with a labeled dollar estimate at $0.01 a credit | None (Stability AI documents no cap) |
| Kimi (Moonshot AI) | Account balance (global platform) | Admin key with billing:read, or an API key | Balance left, in dollars | None (project budgets are your checkmark) |
| Exa | Team credits (Team Management API) | Service key | Balance left, in dollars | None (key budgets and the auto-recharge maximum are your checkmark) |
| ScrapingBee | Plan credit usage | API key | Credits left of the plan, with the renewal date | None (auto renew off is your checkmark) |
| Scrapfly | Account scrape credits | API key (LIVE) | Credits left of the plan, with the period's end | None (extra credit use off on each project is your checkmark) |
| Kie.ai | Account credits | API key | Credits left, with a labeled dollar estimate at about $0.005 a credit | None (key usage caps are your checkmark) |
| Bland AI | Account balance | Restricted API key with only Analytics read (or a full-access key) | Credits left | None (auto refill off is your checkmark) |
| LlamaCloud | Organization usage (this billing period's invoice) | User API key (plus the organization ID if it sees several) | Yes, this billing period, no day | Monthly invoice limit |
| Cartesia | Credit usage | Admin key | No: credits used this month | None (overages off is your checkmark) |
| Together AI | Billing usage report (beta, per organization) | API key | Yes, this month through yesterday | None (auto-recharge off is your checkmark) |
| Fireworks AI | Billing summary | API key (an Inference user's) | Yes | Monthly spend limit |
| Vapi | Analytics: sum of call costs | Private API key | Yes, call costs only | None (auto-reload off is your checkmark) |
| Retell AI | Call list (costs added up) | API key with only History › Read | Yes, call costs only | None (the monthly budget is your checkmark) |
| Browserbase | Project usage | Project API key | No: browser minutes and proxy data, period not stated | None (Browserbase documents no cap) |
| Resend | Quota headers on a domain list | API key with Full access | No: emails used this month | None (overages off is your checkmark) |
| Postmark | Outbound send stats (one server) | Server API token | No: emails sent today and this month | None (Postmark can't cap overage) |
| Mistral | Admin API spend limit (beta, Enterprise) | Admin API key | Yes, this month, no day | Organization spending limit |
| Hugging Face | Organization Inference Providers usage (Enterprise) | Fine-grained token with org billing read, plus the organization name | Yes, up to 2 hours behind | None (the organization spending limit is your checkmark) |
| Custom service | The https address you enter | Whatever the service uses | What its reply says; Kill Cord can't verify it | None |
| Manual entry | You | Nothing | No: not live, never in totals | None |

**About key power.** Anthropic has no read-only key for the cost report: a service account or personal key can do whatever its linked account's role allows, and an Admin API key can also manage your organization. A service account key is the one to use, since it isn't tied to you. Twilio and Neon have no read-only keys either, and none of the balance services offers one: their keys can make paid calls, so give each its own small limit where the service allows. Kill Cord can't know what a custom service's key can do. OpenAI may offer read-only admin keys; choose that if you see it. Kill Cord only reads billing, says this before you save a key, and keeps the key in the Keychain. If a key leaks, revoke it in the provider's console.

## Install

Requires macOS 14 Sonoma or later.

```sh
brew install --cask coreyhaines31/tap/killcord
open -a "Kill Cord"
```

Or download `KillCord.dmg` from [Releases](https://github.com/coreyhaines31/killcord/releases/latest), open it, and drag **Kill Cord** to **Applications**.

## First run

Click the plug in the menu bar, then **Connect a Provider**. In **Settings › Providers**, pick a provider, paste its key, and click **Connect**. Kill Cord checks the key with the provider first, then saves it to the Keychain. Errors appear right there, and the key you typed stays in the field so you can fix it.

| Provider | Where to get the key |
| --- | --- |
| Anthropic | First, if the Console shows an Individual Org, set one up under Settings › Organization (the cost report isn't available to individual accounts). Then Settings › API keys: create a key linked to a service account (recommended) or yourself, not scoped to a workspace. An Admin API key from Settings › Admin keys also works. |
| Google Cloud and Gemini | Turn on the standard usage cost export to BigQuery (Billing › Billing export). Create a service account with BigQuery Data Viewer on the dataset and BigQuery Job User on its project (plus Billing Account Viewer to check budgets), create a JSON key, and paste it with the table's full name. Data appears a few hours after the export starts. Your organization may block service account keys. |
| OpenAI | Platform settings › Organization › Admin keys. |
| Vercel | Account Settings › Tokens. Scope it to the team, and add the team ID. |
| Cloudflare | My Profile › API Tokens. A custom token with only Billing Read, plus your account ID. |
| Twilio | Your Account SID, and a Standard API key and secret (or the Auth Token). |
| Neon | An organization API key and the organization ID. Consumption data needs a Launch, Scale, Agent, or Enterprise plan. |
| Supabase | Nothing to connect. Use the caps audit. |
| OpenRouter | Settings › API Keys. Create a key just for Kill Cord with a small credit limit. |
| Deepgram | An Admin key from the Deepgram Console › project Settings › API Keys. Member keys can't read balances. |
| Runway | An API key (key_…) from the project's API Keys tab at dev.runway.com. |
| SerpApi | The private API key from the SerpApi dashboard. It travels in the request address, as SerpApi requires, and Kill Cord strips it from errors. |
| Bright Data | An API key with the Finance permission level from Account settings › Users and API keys (an admin creates it). |
| ScrapeCreators | The API key from the ScrapeCreators dashboard. |
| Stability AI | An API key from the API Keys page at platform.stability.ai. Keys have no scopes. |
| DataForSEO | The API login and API password from the API Access page (not your dashboard sign-in). |
| Ahrefs | An API key from your Ahrefs account. Your plan needs API access. |
| Firecrawl | An API key from the dashboard's API Keys page. |
| treg | An agent token (`treg org agent-new`, run by an admin), or a personal token plus your team's slug. |
| Monid | An API key from app.monid.ai › Access › API keys. |
| fal | A key with the BILLING preset from fal.ai › Dashboard › Keys. Don't use a FULL key. |
| ElevenLabs | An API key from Settings › API Keys with every endpoint off except User (read). |
| xAI | A management key from the xAI Console › Settings › Management Keys, and the team ID from Settings › Team. A management key can also manage API keys and limits. |
| DeepSeek | An API key from platform.deepseek.com › API Keys, made just for Kill Cord. |
| Apify | An API token from Apify Console › Settings › API & Integrations. Tokens can do everything in the account unless scoped. |
| Tavily | An API key (tvly-…) from the Tavily dashboard, with a small credit limit. |
| Kimi (Moonshot AI) | An Admin key with only the billing:read scope from the Kimi console › Organization › Admin API Keys (verified organizations). An inference API key also works but can spend. |
| Exa | A service key from the dashboard's API Keys › Service keys tab. Exa turns the Team Management API on per team when you ask support. The key can manage your API keys. |
| ScrapingBee | The API key from the dashboard's Account › Manage › API key page. |
| Scrapfly | A project's LIVE API key from the dashboard's Projects page. It travels in the request address, as Scrapfly requires, and Kill Cord strips it from errors. |
| Kie.ai | An API key from kie.ai's API Key page, with small usage caps. |
| Bland AI | A restricted key (org_s_…) with only Analytics read from Settings › API keys. Restricted keys are rolling out by organization; a full-access key also works but can place calls. |
| LlamaCloud | A key from the User API Keys table on LlamaCloud's API Key page (not a project key), plus the organization ID if it sees more than one. Choose the EU region for cloud.eu.llamaindex.ai. |
| Cartesia | An admin key (sk_car_admin_…) from the playground's Admin keys page. Only organization admins can make one, and it can also manage users and invites. |
| Together AI | An API key from any project in the organization. Together turns its billing usage API on per organization; ask support. |
| Fireworks AI | An API key from Settings › Users › API Keys, from a service account or user with the Inference user role, plus the account ID if it sees more than one. |
| Vapi | A private API key from the dashboard's API Keys page. It can do everything in the organization. |
| Retell AI | An API key from Settings › API Keys limited to History › Read. |
| Browserbase | The project's API key from Settings, plus the project ID if it sees more than one. |
| Resend | A Full access API key from resend.com › API Keys. Sending access keys can't read, and a Full access key can manage domains and keys. |
| Postmark | A Server API token from the server's API Tokens tab. It can send email. |
| Mistral | An Admin API key from the Admin Panel's enterprise section (Enterprise plans only). It can manage users, keys and the spending limit. |
| Hugging Face | A fine-grained token from Settings › Access Tokens with only the organization's billing read permission, and the organization's name. Enterprise plan or above. |
| Custom service | The service's balance address, how it wants the key, and where the number is in its JSON. **Test and Save** calls it once first. Addresses on your own network are refused. |
| Manual entry | Nothing to connect: the plan, price, and next renewal date. |

Never paste a key into a chat or an AI agent to set Kill Cord up. If you already have, revoke it and create a new one.

## Reading the panel

| What you see | Meaning |
| --- | --- |
| **Checked 3:42p** | The number is current as of that check. |
| **Last checked 11:42p, not live** | Kill Cord couldn't check since then: your Mac slept, went offline, the check failed, or Kill Cord wasn't running. The line under it says which. |
| **\*** after a total | The total includes a number that isn't live. |
| **Not reported yet** | The provider hasn't reported that period. Not the same as $0. Vercel and Cloudflare report by day, so today often reads this way. |
| **Billing period from Nov 3** | Cloudflare reports by billing period, not calendar month. |
| **data current through 11:00a** | The provider's own freshness stamp, where it gives one. |

Each provider's day and month follow its own billing clock: UTC for most, US Pacific for Google.

## Caps audit

Open **Settings › Caps Audit** (or the caps row in the panel). For each provider you'll see its native controls:

- **Anthropic:** organization spend limit and per-workspace spend limits (hard stops).
- **Google Cloud and Gemini:** spend cap budgets that pause the Gemini API, Vertex AI, or Cloud Run; the AI Studio project spend cap; and budget alerts (alert only).
- **OpenAI:** organization hard limit and project limits (hard stops), and spend alerts.
- **Vercel:** Spend Management with pause production deployments (a partial stop) and its notifications.
- **Cloudflare:** Spend Management limits for Workers and Durable Objects (hard stop), and budget alerts.
- **Twilio:** usage triggers on total price (alert only; Twilio has no native hard cap).
- **Neon:** the spending threshold (alert only) and per-project consumption quotas (hard stop).
- **Supabase:** the Pro plan Spend Cap (a partial stop).

**Open This Setting** goes straight to the console page. Kill Cord never changes a cap for you. Where a provider's API can confirm a cap (OpenAI, Google budgets, Cloudflare, Twilio, Neon), Kill Cord checks it every few hours and on **Check Now**. Everything else is your checkmark, and because caps can be removed, Kill Cord asks you to look again after 30 days. Providers say even hard stops aren't instant, so spend can run a little past a cap.

## Privacy

Kill Cord stores each provider's key in your login Keychain under the service `app.killcord.KillCord.providers`, and sends it only to that provider's billing API over HTTPS. It saves the last spend it read (amounts and times, no keys) in `~/Library/Application Support/Kill Cord`, and your thresholds, caps audit marks, and a random id for each connected provider (no part of the key) in its preferences. Requests use an ephemeral session, so nothing is cached to disk. The only other network request is Sparkle's update check against this repository's releases. No telemetry, no analytics, no account.

## Troubleshooting

**"Last checked … not live" after opening the lid.** Expected: Kill Cord doesn't check while your Mac sleeps. It checks again about 10 seconds after wake. Click **Refresh** to check now.

**"Key rejected."** The key was revoked, expired, or is the wrong kind. OpenAI needs an admin key. Anthropic needs a service account, personal, or Admin API key that isn't scoped to a workspace, in an organization (not an Individual Org).

**"Missing permission."** The key works but can't read billing. The message names what to add (for example, Billing Read on a Cloudflare token).

**Google shows $0 or reads low.** The billing export runs hours behind, typically up to a day, and starts a few hours after you turn it on. Check the table name, and that the service account can read the dataset and run jobs.

**Neon says "Not on this plan."** Neon's consumption API needs a Launch, Scale, Agent, or Enterprise plan.

**No notifications.** Settings › Alerts says so if notifications are off. Turn them on in System Settings › Notifications › Kill Cord.

**The menu bar icon is missing.** On a crowded menu bar, macOS hides icons that don't fit beside the notch. Quit an app or two, or use a menu bar manager.

## Uninstall

In **Settings › General**, click **Remove All…** to delete every key from the Keychain and all local data. Then:

```sh
brew uninstall --cask --zap killcord
```

Without Homebrew, drag **Kill Cord** from Applications to the Trash and trash `~/Library/Application Support/Kill Cord`.

If you deleted the app first, remove the keys yourself: open **Keychain Access**, search for `app.killcord.KillCord.providers`, and delete each item. Or in Terminal, run this once per connected provider (it removes one item each time):

```sh
security delete-generic-password -s app.killcord.KillCord.providers
```

Removing keys from Kill Cord doesn't revoke them. Revoke them in each provider's console if you no longer need them.

## Building from source

Needs Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and SwiftLint (`brew install xcodegen swiftlint`).

```sh
xcodegen generate
xcodebuild -project KillCord.xcodeproj -scheme KillCord -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="" CODE_SIGN_IDENTITY="-" build
open "build/DerivedData/Build/Products/Debug/Kill Cord.app"
```

The provider adapters and all the logic live in `Packages/KillCordCore` (`swift test` there; it also runs on Linux). `swift run killcord-dev` prints the caps catalog and sample data. Debug builds take `--demo` (sample data, labeled as such) and `--snapshot <file.png>`. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Free to use. The source is available under the [Functional Source License 1.1, MIT Future License](LICENSE): you can read, modify, and use it for anything except a competing product, and each version becomes MIT two years after release. The name and icon are covered by [TRADEMARK.md](TRADEMARK.md). Logos are trademarks of their owners and are used only to identify the services Kill Cord reads. Kill Cord is not affiliated with or endorsed by them. Where each logo comes from is in [docs/third-party-marks.md](docs/third-party-marks.md).

## PanelKit design and validation

The menu bar panel uses [PanelKit](https://github.com/coreyhaines31/panelkit) 0.2.1: brushed aluminium in light mode, black anodised in dark mode, and colour for status. See [v1 validation and screenshots](docs/v1-validation.md) for tested builds and remaining release gates.
