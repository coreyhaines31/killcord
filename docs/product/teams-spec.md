# Kill Cord Teams: product spec

Mode: spec (product-manager skill). Written and approved November 17, 2026. Planning only: nothing here is built and no cloud resource exists. Tracking issue: #52. Unit 0 findings: `docs/product/spikes/2026-11-unit-0.md`.

This extends the November 16 plan in `docs/product/cloud-migration.md` from one person to teams. Nothing decided there is reversed.
Read from `origin/development` of `~/code/killcord`: `CLAUDE.md`, `docs/product/spec.md`, `docs/product/cloud-migration.md`, `KeyPower.swift`, `SpendReading.swift`, `LocalAccountSnapshot.swift`, `ConnectionRegistry.swift`, `Provider.swift`, the adapter headers, `site/data/services.json`, and the scratchpad `kc-niche-research.md`.
Provider facts in section 3 come from official docs fetched today. Anything a page did not say is marked unknown.

Profile: collaborative web SaaS (many orgs) with a local macOS utility as a client. Outcomes O1 to O4 apply. O5 applies in a small way (export).

---

## 0. Decisions

All decided by Corey on November 17, 2026. Decisions 1, 3 and 4 were made explicitly. The rest take this spec's recommendation.

| # | Decision | Decided | Why |
|---|---|---|---|
| 1 | Architecture | **Split: Next.js web app + Swift worker on Linux reusing KillCordCore.** Postgres is the contract between them. The web app can only encrypt; the worker is the only process that can decrypt | The eight adapters, their fixtures, `Redactor`, freshness and threshold logic already build and test on Linux. A TS port means two copies that drift each time a provider changes its API. The split also gives the security property the product depends on: the internet-facing app can only encrypt, and the only process that can decrypt has no inbound network. Cost: two runtimes and one more deploy target. Details in section 6 |
| 2 | Where the KMS keys and the worker live | **AWS KMS, one key per paying org. Worker on AWS (Fargate or App Runner) with an IAM role, not a stored access key.** The AWS account is #51 | The worker is the one thing that can read every customer's keys. A role with no long-lived credential is worth the extra ops. Fallback: Railway with an IAM user limited to `kms:Decrypt` |
| 3 | Pricing model | **Flat tiers by cloud connections, unlimited members.** Hypothesis: Solo about $10 a month for 3 connections, Team about $49 a month for 10 | The product gets better with every employee invited. Per seat taxes exactly that. Cost to serve follows connections (polling, one KMS key). Options in section 9 |
| 4 | Trial | **30 days, no card** | A billing month has to close and Google's export runs a day behind, so 14 days often ends before the first month-end picture or the first real alert |
| 5 | The earlier "paid always-on for one person" plan | **Same build, a Solo tier:** a workspace of one is a team of one | No second product to build. The November 16 decisions (hybrid keys, Mac keeps its copy, per-account KMS key) carry over unchanged |
| 6 | Who sees per-person spend by default | **Owner, admin and finance see everyone. A team manager sees their team. A member sees only their own.** One org setting can widen member visibility to team totals | Matches the buyer's job without making the tool feel like surveillance. Every member gets a page that says exactly what the workspace can see about them |
| 7 | Employee machine data (Claude Code and Codex plan usage) | **Last v1 unit, cuttable.** Shares percent of limit used and reset times only | It is the only source for claude.ai Team plan orgs, which have no usage API at all (section 3). It is also the riskiest for trust, so it ships last and smallest |
| 8 | May an admin paste a provider key into the web dashboard | **Yes, with a fresh sign-in (10 minutes) and the key-power warning.** The Mac move stays the preferred path | Finance and non-Mac admins need it. The endpoint is write-only either way |
| 9 | A removed member's data | **Provider-reported spend stays with the org, shown as "former member". Data they shared from their Mac is deleted** | The first is the company's billing data. The second was theirs to give |
| 10 | Repo and license for the cloud | **Private repo for the web app and worker. New attribution adapters go into public KillCordCore** | Anyone can read the code that touches provider APIs and handles keys. The business logic stays private |
| 11 | Alert channels in v1 | **Email and the Mac app. Slack next** | A Slack webhook URL is one more key to hold. Add it once the vault is proven |
| 12 | The bar before holding a stranger's admin key | **Dogfood on our own orgs first. Before the first outside key: an outside security review, one restore drill, an incident runbook** | An Anthropic Admin key can create API keys and manage members. A leak is a company-ending event for a product called Kill Cord |

---|---|---|---|
| 1 | **Architecture (the one to confirm).** Next.js app plus a Swift worker, or port the adapters to TypeScript and run everything in Next.js | **Split: Next.js web app + Swift worker on Linux reusing KillCordCore.** Postgres is the contract between them | The eight adapters, their fixtures, `Redactor`, freshness and threshold logic already build and test on Linux. A TS port means two copies that drift each time a provider changes its API. The split also gives the security property the product depends on: the internet-facing app can only encrypt, and the only process that can decrypt has no inbound network. Cost: two runtimes and one more deploy target. Details in section 6 |
| 2 | Where the KMS keys and the worker live | **AWS KMS, one key per paying org. Worker on AWS (Fargate or App Runner) so it gets its decrypt permission from an IAM role, not a stored access key.** Settle in the unit 0 spike | The worker is the one thing that can read every customer's keys. A role with no long-lived credential is worth the extra ops. Fallback: Railway with an IAM user limited to `kms:Decrypt` |
| 3 | Pricing model | **Flat tiers gated by cloud connections, unlimited members.** Not per seat, not a percentage of spend | The product gets better with every employee invited (they see their own spend, they can opt in to share). Per seat taxes exactly that. Cost to serve follows connections (polling, one KMS key). Options in section 9 |
| 4 | Trial length | **30 days, no card** | A billing month has to close and Google's export runs a day behind, so 14 days often ends before the first month-end picture or the first real alert |
| 5 | What happens to the earlier "paid always-on for one person" plan | **Same build, a Solo tier:** a workspace of one is a team of one | No second product to build. The November 16 decisions (hybrid keys, Mac keeps its copy, per-account KMS key) carry over unchanged |
| 6 | Who sees per-person spend by default | **Owner, admin and finance see everyone. A team manager sees their team. A member sees only their own.** One org setting can widen member visibility to team totals | Matches the buyer's job without making the tool feel like surveillance. Every member gets a page that says exactly what the workspace can see about them |
| 7 | Employee machine data (Claude Code and Codex plan usage) in v1 or right after | **Last v1 unit, cuttable.** Shares percent of limit used and reset times only | It is the only source for claude.ai Team plan orgs, which have no usage API at all (section 3). It is also the riskiest for trust, so it ships last and smallest |
| 8 | May an admin paste a provider key into the web dashboard | **Yes, with a fresh sign-in (10 minutes) and the key-power warning.** The Mac move stays the preferred path | Finance and non-Mac admins need it. The endpoint is write-only either way |
| 9 | A removed member's data | **Provider-reported spend stays with the org, shown as "former member". Data they shared from their Mac is deleted.** | The first is the company's billing data. The second was theirs to give |
| 10 | Repo and license for the cloud | **Private repo for the web app and worker. New attribution adapters go into public KillCordCore.** | Anyone can read the code that touches provider APIs and handles keys. The business logic stays private |
| 11 | Alert channels in v1 | **Email and the Mac app. Slack next.** | A Slack webhook URL is one more secret to hold. Add it once the vault is proven |
| 12 | The bar before holding a stranger's admin key | **Dogfood on your own orgs first. Before the first outside key: an outside security review, one restore drill, an incident runbook.** | An Anthropic Admin key can create API keys and manage members. A leak is a company-ending event for a product called Kill Cord |

---

## 1. Brief

### Audience

| Who | Buyer or user | Job | Today's workaround |
|---|---|---|---|
| Founder or CTO at a 5 to 50 person company | Buyer, admin | "Know what we spend on APIs, who and what is driving it, and hear about a runaway before the invoice" | Logs in to five consoles, or doesn't. Finds out from the card statement |
| Finance or ops | User, sometimes buyer | "Month-to-date and last month by provider, team and person, exportable, without console logins I shouldn't have" | Asks the CTO for screenshots. Reads invoices after the fact |
| Engineering manager | User | "See my team's spend and who is near a budget" | Provider console if they have access. Slack questions |
| Employee (developer, marketer running agents) | User | "See my own number so I am not surprised by a message from finance" | Usually nothing. Individual usage is invisible to them |

Larger companies already have Vantage, CloudZero, Datadog and others (Anthropic lists seven such partners on its usage docs). The wedge here is small companies that will not run a FinOps platform: connect in minutes, mapped to people, with a Mac client the team may already use.

### Useful outcome

An admin connects a provider and within the first session sees up to 12 months of history, split by key, project and person where the provider reports it, with the rest clearly "unassigned". Finance gets one page and a CSV. Each employee can see their own number. A budget crossing reaches the right person by email even with every laptop closed.

### Critical journeys

1. **Admin first use:** sign up, create workspace, connect the first provider, see history, assign keys and projects to people, set one budget, invite the team.
2. **Return:** finance or a manager opens the dashboard, reads month-to-date by team, person and provider, exports.
3. **Employee:** accepts the invite, sees "My spend", optionally installs the Mac app and optionally shares plan usage.
4. **Recovery:** a key is revoked or expires at the provider. Admins are told, the connection shows the error, a replacement key keeps the id and history.
5. **Offboarding:** a member is removed. Access ends at once and the admin gets a list of keys to rotate.
6. **Solo to team:** a person with the free Mac app moves chosen connections into an org without pasting a key again.
7. **Trial end and billing.**

### v1 in

| Requirement | Acceptance |
|---|---|
| Orgs, members, four roles, teams with managers, invites, many orgs per user, personal workspace | Section 4 matrix passes as automated tests, including every negative test |
| Org connections held in the cloud, polled 24/7 | A connection added Friday shows weekend spend Monday with no Mac awake |
| Attribution for Anthropic and OpenAI by key, workspace or project, and person | Sum of attributed plus unassigned equals the provider's total for the same range, to the cent |
| Breakdown by project, subaccount or label for Google, Vercel, Twilio, Neon | Same reconciliation rule. Shown as "assigned by an admin", never as measured per person |
| Assign keys, projects and workspaces to a member or team | A reassignment is dated and audited. History before the date keeps the old owner |
| Budgets and alerts at org, provider, connection, team, person, and key or project level | Each threshold fires once per period, by email and to signed-in Macs. A test alert works |
| Dashboard: org, team, person, provider views. "My spend" for members. CSV export | A member cannot load another member's page by changing the URL |
| Mac app: sign in, pick workspace, move connections (admins), My spend, org alerts | The free app with no account behaves exactly as today |
| Audit log | Every key add, replace, remove, role change, assignment, export and member removal has a row |
| Billing: trial, Stripe subscription, entitlements | A lapsed org stops polling and the UI says so |
| Opt-in employee sharing of plan usage (cuttable) | Nothing leaves the Mac until the employee turns it on. What is sent equals the preview |

### v1 out

- Any proxy or gateway. Any change to provider settings: Kill Cord stays read-only, so no auto-stop.
- Cost estimates from token counts. A number is the provider's or it is absent.
- Generic custom JSON connections in the cloud (a user-supplied URL fetched by our server is an SSRF path). They can ship in the local Mac app first.
- Niche credit services from `kc-niche-research.md` beyond the eight built in. Add them after the core is proven.
- SSO/SAML, SCIM, custom roles, Slack and SMS alerts, an API or MCP for outside agents, an "ask your spend" chat.
- Windows or Linux desktop clients. Those employees use the web.
- Readings-only sync for personal workspaces (decided on November 16 as the free cloud tier). It reuses this build and can follow. Nothing here reverses it.

### Better-model test

Better models and more agents mean more API spend by more people, so this gets more useful. The product has no AI in it. What it contributes: key custody, provider adapters that stay current, the mapping from keys and projects to people, permissions, and alert delivery. What would make it obsolete: providers shipping good cross-provider team dashboards (they won't cross providers), or FinOps incumbents moving down to 10-person companies. Not a moat claim.

### Stack

| Part | Choice | Note |
|---|---|---|
| Web app, API for the Mac | Next.js App Router, TypeScript, Tailwind, shadcn/ui | Default |
| Data | Prisma ORM, Prisma Postgres, UUID keys, `Decimal` for money | Default. Whether Prisma Postgres supports custom roles and row-level security is **unverified**: check in unit 0 |
| Auth | Better Auth, organization plugin (with teams), Sign in with Apple, email link | Decided November 16. Add Google sign-in for work accounts (assumed) |
| Polling worker | Swift on Linux, KillCordCore as a package dependency | **Departure from the TS default.** Decided November 16, reasons in section 6 |
| Key encryption | AWS KMS | **Not in the defaults.** Decision 2 |
| Jobs | The worker leases due connections from Postgres (`FOR UPDATE SKIP LOCKED`). No queue service | Open choice, kept minimal |
| Billing | Stripe, Customer Portal | Default |
| Email | PostShiba, `mail.killcord.app` | Default |
| Analytics | TracerKit + Headstream on the web app only | The Mac app stays zero-telemetry |
| Feedback screenshots | Private bucket (Cloudflare R2 assumed) | Open choice |

---

## 2. What "how employees use them" can honestly mean in v1

Two kinds of attribution, labeled differently everywhere in the UI:

- **Reported:** the provider's API names the user, service account or key. Available for Anthropic and OpenAI only.
- **Assigned:** an admin maps a key, project, workspace, subaccount or label to a person or team. Available for every provider with a breakdown.

Anything neither reported nor assigned is **Unassigned** and always visible, so totals reconcile.

Honest limits to state in the product:

1. Per-person dollars from Anthropic lag. The API that reports by person typically refreshes within 4 hours and can take 24. Values can change until about 7 days after month end. The fast API (about 5 minutes) only splits by workspace.
2. Subscription seats are mostly invisible. Claude Code used through a Pro, Max or Team subscription is not in the Console org's data. claude.ai Team plan orgs have no usage API. Only Claude Enterprise exposes per-user data. For everyone else, the employee's opt-in from their Mac is the only source, and it reports percent of plan limit, not dollars.
3. Google, Vercel, Cloudflare, Twilio and Neon have no per-user or per-key data. A "person" there means "the owner an admin assigned to that project".
4. It is spend and volume, not activity. Kill Cord never sees prompts, code or conversations, and should say so.

---

## 3. Attribution research (official docs, checked November 17, 2026)

| Provider | API | Breakdown it gives | Key it needs | Freshness |
|---|---|---|---|---|
| **Anthropic, Console org** | Usage and Cost Analytics API (beta): `GET /v1/organizations/analytics/cost` and `/usage`, header `anthropic-beta: analytics-usage-cost-2026-08-24` | `group_by[]` up to five of: `actor` (user, service account, federated identity, or the key itself for legacy workspace keys), `actor_type`, `api_key_id`, `workspace_id`, `model`, `service_tier`, `context_window`, `inference_geo`, `speed`, product, plus `cost_type` and `token_type` on cost. Buckets 1m, 1h, 1d. `amount` (after discounts) and `list_amount`, cents as decimal strings | Admin API key, an `org:admin` OAuth token, or a personal or service account key not scoped to a workspace. No read-only option. Docs advise a dedicated key with an expiration, or Workload Identity Federation | "Typically refreshes within 4 hours ... can take up to 24 hours." Revised until about 7 days after month end. Every response carries `data_refreshed_at`. History from January 1, 2026, 365-day lookback, 31 days per request |
| Anthropic, Console org | Legacy `cost_report` (what the Mac app uses today) | `workspace_id`, `description` only. Daily | Same | "Typically appears within 5 minutes." Polling once a minute is supported |
| Anthropic, Console org | Legacy `usage_report/messages` | Tokens (not dollars) by `api_key_id`, `workspace_id`, `model`, `service_tier` and more. The migration table also lists `account_id` and `service_account_id` grouping | Same | About 5 minutes. 1m, 1h, 1d |
| Anthropic, Console org | Claude Code Analytics: `GET /v1/organizations/usage_report/claude_code` | One day per call. Per actor (`email_address` or `api_key_name`): sessions, lines, commits, PRs, tool accept/reject, tokens and **estimated** cost by model | Same | Up to 1 hour. "This API doesn't return" usage from people signed in with a Pro, Max, Team or Enterprise subscription |
| Anthropic, Console org | Admin API lists: users (id, email, role), API keys (`created_by`, `principal` user or service account, `scope` workspace, `partial_key_hint`, `status`), workspaces | The join from key to person | Same | Live |
| **Anthropic, Claude Enterprise** | Same Analytics API, plus Enterprise Analytics (per-user daily activity) | Per user cost and usage. Cost endpoints apply to usage-based plans; on seat-based plans "they reflect usage credits only" | **Analytics API key with the `read:analytics` scope**, created by the primary owner. Read-only by scope | Cost: 4 to 24 hours. Activity: next day about 13:00 UTC. 60 requests a minute per org |
| Anthropic, Claude Enterprise | Spend Limits API | Each member's effective monthly limit and period-to-date spend | Admin key with `read:spend_limits` | Not stated. Enterprise only |
| **Anthropic, claude.ai Team plan** | None | The Admin API "isn't available to organizations on the claude.ai Team plan" | n/a | n/a |
| **OpenAI** | `GET /v1/organization/costs` | `group_by`: `project_id`, `user_id`, `api_key_id`, `line_item`, `api_source`. Daily buckets only, up to 180 per page. Filters: `project_ids`, `api_key_ids`. Combining `user_id` with project grouping "depends on the organization and requested time range" (else HTTP 400) | Admin API key. Whether it can be made read-only: **not stated on the pages read today** (the app's `keyPower` says "if chosen at creation") | **Not documented** |
| OpenAI | `GET /v1/organization/usage/completions` (and sibling usage endpoints) | Tokens and requests by `project_id`, `user_id`, `api_key_id`, `model`, `batch`, `service_tier`, `api_source`. 1m, 1h, 1d | Admin API key | Not documented |
| OpenAI | `GET /v1/organization/projects/{id}/api_keys` | Each key's `owner`: a user (`id`, `email`, `name`, `role`) or a service account, `last_used_at`, `redacted_value` | Admin API key | Live |
| OpenAI | What `user_id` means (the member who owns the key, or something else) | **Unknown.** The reference says only "the user ID of the grouped usage result". Verify with a real org in unit 7 before showing it as a person | | |
| **Google Cloud and Gemini** | Billing export in BigQuery | `project.id`, `project.labels`, resource `labels`, `tags`, `service`, `sku`. **No user, principal or API key column.** The detailed export adds resource-level rows | Service account with BigQuery read (read-only) | "Typically ... within a day, but can sometimes take more than 24 hours." Labels count only from the day they were applied |
| **Vercel** | `GET /v1/billing/charges` (FOCUS v1.3) | Per charge, daily, with `Tags` carrying ProjectId and ProjectName. No per-user data. One team per call | Team access token whose role can see billing. Cannot be scoped to billing only | Not documented |
| **Cloudflare** | `GET /accounts/{id}/billable-usage` (Alpha) | Per account by `ServiceName`. No per-user or per-token split. Pay-as-you-go only | API token with Billing Read (read-only) | Daily. **Status unclear:** a search of the API reference today showed a "deprecated" mark on the index for these endpoints. Recheck before building on it |
| **Twilio** | Usage Records | Per account and subaccount (`account_sid`), by category. A parent reads its subaccounts by default. No per-key or per-user split | API key and secret, or the Auth Token. No read-only key documented | `as_of` timestamp only |
| **Neon** | `GET /consumption_history/v2/projects` | Per project, hourly, daily or monthly. **Usage units, never dollars** | API key for the org. Not read-only | About 15 minutes (per the adapter's notes) |
| **Supabase** | None | No usage API | n/a | n/a |

What this decides:

- **Per-person spend is real for Anthropic (Console and Enterprise) and probably OpenAI**, pending the `user_id` check. Ship those two first.
- **Poll two cadences for Anthropic:** the 5-minute legacy cost report for org and workspace totals and fast alerts, and the analytics API hourly for the per-person and per-key split. Re-pull the trailing 40 days once a day until the month is final.
- **Backfill on connect.** Anthropic allows 365 days, OpenAI pages of 180 days, Vercel a year, Neon 60 days. A new org sees history in the first session, not an empty chart.
- **Steer customers to the weakest key that works:** `read:analytics` for Claude Enterprise, Billing Read for Cloudflare, a viewer service account for Google. For Anthropic Console there is none, so recommend a dedicated key with an expiration and remind before it expires.
- **Person and key budgets on Anthropic are next-morning alerts, not live ones.** Say so on the budget form.

---

## 4. Org model and access

### Entities

- **User:** a person. One sign-in, many memberships. Gets a personal workspace at sign-up (holds nothing paid).
- **Organization (workspace):** the tenant and the billing scope. Owns connections, attribution, budgets, alerts, audit log, its KMS key.
- **Membership:** user in org with one role: `owner`, `admin`, `finance`, `member`.
- **Team:** a group inside an org (Engineering, Marketing). A member can be in several. `manager` is a flag on a team membership, not a fifth role.
- **Device:** a Mac signed in by a user. Its token is tied to the user, not to an org, and every call names the org and is checked against the live membership.
- **Connection:** one provider account's key, owned by the org. Its id is the Mac's `ConnectionRecord` UUID when it was moved from a Mac.
- **Attribution unit:** something the provider breaks spend down by: a key, project, workspace, actor, subaccount or label. An **assignment** maps a unit to a member or team from a date.
- **Invitation:** email, role, optional teams, expires in 7 days, single use.

### Access matrix

| Operation | Owner | Admin | Finance | Team manager | Member | Removed member | Other tenant |
|---|---|---|---|---|---|---|---|
| See org, provider and connection totals | yes | yes | yes | no (own team total only) | no | no | no |
| See any person's spend | yes | yes | yes | own team | self only | no | no |
| See team totals | yes | yes | yes | own team | own teams if the org setting allows | no | no |
| See key hints ("Ending in 0001") and key power | yes | yes | no | no | no | no | no |
| Add, replace or remove a connection key | yes | yes | no | no | no | no | no |
| Read a stored key | **nobody, by any path** | | | | | | |
| Assign units to people and teams | yes | yes | no | propose only (later) | no | no | no |
| Create or edit budgets and alert routes | yes | yes | yes | own team's | own personal alert only | no | no |
| Export CSV | yes | yes | yes | own team | own | no | no |
| Invite, remove, change roles | yes | yes, not owners | no | no | no | no | no |
| Manage billing and plan | yes | no | yes | no | no | no | no |
| Read the audit log | yes | yes | no | no | no | no | no |
| See a member's shared machine data | yes | yes | no | own team | self | no | no |
| Turn a member's machine sharing on | **only that member, on their Mac** | | | | | | |
| Delete the org, transfer ownership | owner, with a fresh sign-in and typed confirmation | no | no | no | no | no | no |

Rules: deny by default on the server. One policy function per operation, called by pages, server actions, the device API and exports alike. The last owner cannot leave or be demoted. Admins cannot remove owners.

### Negative tests (all automated, section 10)

1. Org A's member requests org B's connection, person page, export or audit row by id: 404, same body as a missing id.
2. A member opens another member's person page in their own org: denied.
3. A team manager requests a member outside their team: denied.
4. A finance user requests key hints or the audit log: denied.
5. A member is removed while their dashboard is open: the next request fails, and so does their Mac's next call.
6. A member is demoted from admin to member: an already-open "replace key" form is rejected on submit.
7. An invite link is used twice, used after expiry, or used by a different email than invited: rejected.
8. A device token from org A's former member is replayed against org A: rejected. Against the user's other org B, where they are still a member: still works.
9. Adding a provider account that already exists in another org reveals nothing about that org.
10. Any role, any endpoint, any export: no response ever contains a stored key or a non-secret credential field value.
11. A removed member's queued CSV export job checks membership again before it runs.
12. A lapsed org's polling stops, and its dashboard goes read-only.

### Removal, and what happens to data

| Thing | On member removal |
|---|---|
| Sessions and device tokens for that org | Revoked at once |
| Connections they added | Stay. The org owns them. The audit log keeps who added each |
| **Keys they moved from their Mac** | Their Mac still has its copy, and Kill Cord cannot take it back. The removal screen lists those connections with "Rotate this key at the provider" and tracks each as done or not |
| Provider-reported spend under their email or keys | Stays, shown as "Former member" |
| Assignments to them | Kept for history, flagged "owner left" so an admin can reassign |
| Data they shared from their Mac | Deleted within 24 hours |
| Their account and other workspaces | Untouched |

---

## 5. Key custody

Carried over unchanged from November 16: envelope encryption (AES-256-GCM, one data key per stored credential, wrapped by the org's KMS key with org id and connection id as encryption context), the Mac keeps its copy, nothing is ever sent back down, stopping monitoring deletes the ciphertext at once.

Team additions:

- **Who:** owner and admin can add, replace and remove. Finance and members never see that a key exists beyond the provider's name.
- **Two ways in:**
  - *From a Mac (preferred):* the existing review screen, shown to admins, with a workspace picker. Each connection's switch is off. `LocalAccountSnapshot` supplies the rows. The key is read from the Keychain at that moment and sent to the write-only endpoint. The connection keeps its UUID.
  - *Pasted on the web:* for admins without a Mac. Needs a sign-in within the last 10 minutes. Same form fields as the app (`ProviderInfo.fields`).
- **Before storing:** the cloud validates the key with the provider, shows the key-power line from `ProviderID.keyPower`, and matches the provider's account identity against the org's connections so the same account is not stored twice.
- **Key-power copy** (no em dashes):
  - `readOnly`: "This key can only read billing. Good to store."
  - `readOnlyIfChosen`: "Check that you created this key as read-only."
  - `canManage`: "This key can also manage your Anthropic organization, including members and API keys. Anthropic has no read-only key for cost data. Create a key just for Kill Cord, set an expiration, and revoke it if anything looks wrong."
- **Rotation:** "Replace key" keeps the connection id, history, assignments and budgets. If the provider returns an expiry (Anthropic keys have `expires_at`), remind admins 14 and 3 days before.
- **Audit log:** who, when, from which device or browser, which connection, what action, result. Also one row per day per connection summarizing the worker's reads (count, last result), with the full poll log kept 30 days.
- **Solo user moving into an org:** a member who is not an admin cannot move a key in. Their Mac's connections stay personal. If they should be org connections, an admin adds them (or the member is made admin). No "request to add" flow in v1.
- **One connection, one org.** To watch the same provider account from two orgs, add it twice with two keys.

---

## 6. Architecture (decision 1)

```
Mac app ──device token──▶ Next.js app (Vercel) ──▶ Postgres ◀── Swift worker (no inbound network)
browser ──session──────▶   can encrypt only          ▲             can decrypt only
                            Stripe, PostShiba         │             calls provider APIs
                                   │                  │                    │
                                   └──── AWS KMS: Encrypt ─────┴──── AWS KMS: Decrypt
```

- **Next.js app:** dashboard, auth, orgs, billing, the device API (`/v1/devices`, `/v1/connections/{id}`, `/v1/me/spend`, `/v1/machine-readings`), email. To store a key it makes a random data key locally, encrypts the credential, wraps the data key with `kms:Encrypt`, and writes both. Its IAM identity has no `kms:Decrypt`. Its database role cannot `SELECT` the ciphertext columns.
- **Swift worker:** leases due connections, decrypts in memory for one request, calls the provider through KillCordCore, writes spend rows and a poll log row. Its database role can read ciphertext and write facts, and cannot read users, sessions or billing. Outbound traffic is allowed only to the providers' API hosts, KMS and Postgres.
- **Alerts:** the worker evaluates budgets after each write and inserts alert rows. The web app sends them (it owns PostShiba). The worker never sends mail.

| | Split (recommended) | All TypeScript |
|---|---|---|
| Adapters | Reuse eight tested adapters and their fixtures | Rewrite eight, then keep two copies in step |
| Key exposure | Decrypt lives in one small process with no inbound network | Decrypt lives in the internet-facing app's runtime |
| Ops | Two deploy targets, a container to keep patched | One |
| New attribution adapters | Written once in KillCordCore, usable by the Mac app later | Written in TS, the Mac app can't use them |
| Hiring and agents | Swift on the server is less common | Everything in the default stack |

If Corey prefers one runtime, the fallback that keeps the security property is a second, private TypeScript service for the worker. That is the same split with the adapters rewritten, so it costs more and gains little.

---

## 7. Budgets, caps and alerts

- **Scopes:** org total, provider, connection, team, person, attribution unit (a key or project). **Periods:** day and month, on the provider's billing clock (`ProviderInfo.billingTimeZone`).
- **Thresholds:** 50, 80 and 100 percent by default, editable. Each fires once per period per budget (the Mac app's `ThresholdPlanner` rule, kept server-side so two Macs never double-fire).
- **Who hears:** the budget's owner and anyone added to it. A person budget always includes the person.
- **Channels:** email and a notification on signed-in Macs. A failed send is shown as failed and retried, never shown as delivered.
- **Every budget form says:** "Alert only. Kill Cord can't stop spending. Hard stops live in your provider's settings." Person and key budgets on Anthropic add: "Anthropic reports per-person cost a few hours behind, sometimes a day."

What can actually be enforced, and by whom:

| Provider | Native hard stop | Kill Cord's part |
|---|---|---|
| OpenAI | Org and project monthly hard limits. "Enforcement is not instantaneous" | Reads the org limit by API and shows on or off. Project limits: API readability unknown |
| Anthropic Console | Workspace and org spend limits, set in the Console | Not readable by API. Self-reported in the caps audit |
| Claude Enterprise | Per-member monthly spend limits | Readable with `read:spend_limits`. Show each member's limit beside their spend (later) |
| Google Cloud | Budget spend caps | Readable. Shown in the caps audit |
| Cloudflare | Spend policies with `usage_block` | Readable |
| Vercel | Spend Management pause | No API. Self-reported |
| Twilio, Neon | Triggers and thresholds that notify only | Shown as "alert only at the provider too" |

The org gets one caps audit (the Mac app's `CapsCatalog`), per connection, so an admin sees which hard stops are on.

---

## 8. Experience: states per journey

Design direction is a proposal: the web dashboard follows the Brushed family look of killcord.app (metal, black, color only in the lights), built on shadcn/ui. Route to the frontend-design and web-design-guidelines skills at build time. Errors and consequences stay inline.

| Journey | State | What the user sees | Primary action |
|---|---|---|---|
| Admin first use | Empty org | "No providers connected yet. Connect one to see up to 12 months of spend." Says a key will be stored encrypted and never shown again | Connect a provider |
| | Key invalid | Inline error from the fixed `SpendError` text, input kept, key never echoed | Fix and retry |
| | Key lacks access | "This key can't read the cost report. Use an Admin API key." with the provider's link | Open provider settings |
| | Key can manage the org | The `canManage` warning above the Save button, not in a tooltip | Store this key |
| | Validating, then backfilling | "Checking with Anthropic", then "Loading history: 3 of 12 months". Progress is not success | none |
| | First data, nothing assigned | Totals, and an "Unassigned $412.80" row with "Assign 14 keys to people" | Assign |
| | Suggested matches | "9 keys match members by email." Each row shows key name, provider email, member | Confirm matches |
| | Double submit on invite or key save | Button disabled while sending. Same idempotency key on retry | none |
| Return | Fresh | Per provider: "Checked 4 min ago. Anthropic per-person data as of 9:00 UTC" | Read, export |
| | Provider lagging | "Google's billing export is usually a day behind. Today may be incomplete." Missing is shown as "not reported", never $0 | none |
| | Partial | One provider failed, the rest show. Banner names the one that failed and since when | View connection |
| | Month not final | "October can still change until about November 7." | none |
| | Export | "Preparing", then a download. Covers only what the viewer may see | Download |
| Employee | Invite accepted, nothing attributed | "Nothing is attributed to you yet. Your admin assigns keys and projects." | See what your workspace can see |
| | My spend | Own number by provider and key, with Reported or Assigned labels | none |
| | Transparency page | "Your workspace can see: spend on keys assigned to you, and usage Anthropic or OpenAI report under your work email. It can't see prompts, code or conversations. Sharing from your Mac is off." | none |
| | Denied page | "You don't have access to this." No hint whether the thing exists | Back to My spend |
| Recovery | Key revoked or expired | Connection card: "Anthropic rejected this key on Nov 17 at 14:02. Spend is not being watched." Email to admins once, not every poll | Replace key |
| | Provider outage or rate limit | "Anthropic isn't answering. Last good reading 40 min ago. Retrying." Backs off per `RefreshScheduler` | none |
| | Our worker is down | Every provider goes stale together. Banner: "Kill Cord's monitor is delayed. Alerts may be late." | Status page |
| Offboarding | Confirm removal | Lists what ends now, what stays, and keys to rotate | Remove member |
| | After | Checklist of keys to rotate, each with the provider link and a "Rotated" tick that prompts a key replace | Rotate |
| Solo to team (Mac) | Not an admin | "Only admins can add provider keys to Acme. Your connections stay on this Mac." | Done |
| | Admin review | One row per connection, key power, switch off by default. "Your Mac keeps its copy." | Move selected keys |
| | Upload interrupted | Moved ones marked "Always on", the rest unchanged. Safe to run again | Try again |
| | Offline | Cached numbers marked "not live". Nothing queued silently | none |
| Machine sharing | Off (default) | "Not sharing. Your workspace sees nothing from this Mac." | Preview what would be shared |
| | Preview | The exact payload, readable: tool, window, percent used, reset time. "Never shared: prompts, files, project names." And who can see it, by role | Start sharing |
| | On | A visible "Sharing with Acme" line in the panel, last sent time | Stop sharing |
| | Stopped | "Stopped. Delete what was already shared?" | Delete / Keep |
| Trial and billing | Trial, days 1 to 23 | A quiet "Trial: 24 days left" in settings only | none |
| | Last 7 days | Banner to owner and finance with the plan the org would land on | Choose a plan |
| | Trial ended, no plan | Dashboard read-only. "Monitoring is paused. Your keys are kept encrypted for 14 days, then deleted." Emails at 7, 3 and 1 days | Choose a plan |
| | Payment failed | Banner to owner and finance. Monitoring continues for 7 days of Stripe retries | Update card |
| | Over the plan's connections | The extra connection is refused with the reason beside the button | Upgrade |
| | Cancel | One screen, says what is deleted and when. No retention maze | Cancel plan |

Actions that need a preview or confirmation: storing a key, replacing or removing a key, removing a member, changing a role to admin or owner, turning on machine sharing, deleting shared data, deleting the org, canceling.

---

## 9. Pricing and trial (decided November 17: decisions 3 and 4)

Reference points from the existing spec (dated November 15, not rechecked today): Costbrake Team $39 a month, Vantage Pro $30 a month and free under $2,500 tracked.

| Model | For | Against |
|---|---|---|
| **Per seat** | Familiar. Grows with the company | Punishes inviting employees and finance viewers, which is where the value is. Invites a "seats vs tracked people" argument, since spend is attributed to people who never log in |
| **Per cloud connection, flat tiers, unlimited members** (recommended) | Follows cost to serve. Free to invite everyone. Easy to explain: "how many provider accounts do you watch" | Weakly tied to company size. A big company with two provider accounts pays little. A later Business tier (SSO, audit export, longer history) covers that |
| **By tracked spend** | Tracks value | The existing spec already says "do not price as a percentage of spend". Feels like a tax, bills swing, and it rewards us when the customer overspends |

Starting hypothesis (unmeasured): Solo, 1 member, 3 cloud connections, about $10 a month. Team, unlimited members, 10 cloud connections, about $49. Business later. Annual can wait.

Trial options: 14 days with a card, 14 days without, 30 days without (recommended), or "free until the first full calendar month closes". At trial end the org goes read-only as in section 8.

---

## 10. Trust

### What the system ingests

Provider keys that can manage whole organizations. Spend broken down by named employees. Work emails from provider user lists. Optional plan-usage readings from employees' Macs. Payment details go to Stripe, never to us.

### Threat model

| Threat | Control | Residual risk |
|---|---|---|
| Web app compromised (dependency, SSRF, auth bug) | It holds no decrypt permission and cannot select ciphertext. The worst case is reading spend data and writing bad keys | Spend data and emails of every org are exposed. Real, and the reason for row-level isolation and minimal PII |
| Worker compromised | No inbound network, outbound allowlist, per-org KMS keys with encryption context, CloudTrail alarm on decrypt volume or decrypts outside the poll schedule | It can decrypt every key while compromised. This is the core risk. Mitigate by steering to read-only keys and by a tested "revoke everything" runbook |
| Database or backup stolen | Ciphertext only, useless without KMS. Deleting an org's KMS key makes its backups unreadable | Spend data in the dump is readable |
| Tenant A reads tenant B | One policy core, org-scoped queries, row-level security as a second layer if Prisma Postgres supports it, cache keys that include org and audience | A missed route. Covered by the route manifest test in section 11 |
| Malicious or removed member | Live membership check on every request and every job, device tokens revoked on removal | A copy of a key on their own Mac. Covered by the rotate checklist |
| Stolen session or device token | Fresh sign-in for key changes, role changes and deletes. Tokens only in headers. Keys never returned | Reads that member's view of spend until revoked |
| Hostile provider response (echoes the key, huge body) | `Redactor`, fixed error strings, `KeySafetyTests` ported to the worker, response size limits | Low |
| Insider (Corey, an agent with prod access) | No human or agent identity has `kms:Decrypt`. Support views show hints only. Production access is logged | Whoever administers the AWS account can grant themselves decrypt. Guard with MFA, a separate account and CloudTrail alerts |
| Invite or email abuse | Rate limits per org and per IP, single-use expiring invites, no account enumeration | Low |
| Stripe webhook forgery or replay | Signature check, event id dedupe, reconcile job | Low |
| Admin pastes a key into the wrong org | Org name on the form and in the confirmation. Remove deletes at once | Low |

Rules that follow: the cloud never changes a provider setting. The worker's HTTP client allows only GET to known provider paths (plus the BigQuery query POST). No user-supplied URLs. Keys, tokens and spend amounts stay out of URLs, logs, analytics and error text.

### Employee privacy

- The company's provider data is the company's. Kill Cord shows members what is visible about them and to which roles.
- Machine data is the employee's. Off by default, turned on only on their Mac, payload shown first, stoppable and deletable by them, deleted when they leave. An admin cannot turn it on, require it, or see who declined (they see "sharing" or nothing).
- No prompts, code, file paths, repo names, or per-session timelines, ever. v1 sends per tool and window: percent used, reset time, plan name, once an hour.
- Where the readings come from: assumed to be Fuel Gauge on that Mac through its `fuelgauge` command. Whether it has a machine-readable output is **unverified**. If it does not, this unit waits.
- Some countries require notice or consultation before employee monitoring. Ship a short notice template for admins and a line in onboarding. This is not legal advice and needs a lawyer's read before selling in the EU.

### Data lifecycle

| Data | Kept | Deleted |
|---|---|---|
| Stored keys | While the connection is on | At once on remove or replace. 14 days after a trial or plan ends. With the org |
| Spend facts (daily) | 24 months on Team (proposed) | With the org, 30 days after deletion is requested |
| Poll log | 30 days | Rolling |
| Audit log | 24 months | With the org |
| Machine readings | 90 days (proposed) | When the member deletes them or leaves |
| Sessions, device tokens | Until revoked or 90 days idle | On removal or sign-out |
| Org deletion | 30-day window to undo (keys are deleted on day 0, not day 30) | Then rows purged and the KMS key scheduled for deletion |

Backups cannot be purged row by row. Say so in the privacy page: deleted data ages out of backups within the backup window, and stored keys in backups are unreadable once the org's KMS key is gone.

### Outcomes

| | Applies | v1 |
|---|---|---|
| O1 orgs and roles | Yes | Section 4 |
| O2 feedback to the builder | Yes | In-dashboard form: text and screenshot, private upload, preview before send. Video is a gap to accept or schedule |
| O3 security | Yes | This section. Outside review before the first outside key |
| O4 analytics | Yes, web only | TracerKit + Headstream. Events for sign-up, org created, connection added (provider only), first data, assignment made, budget created, invite sent and accepted, trial to paid. Payloads carry org id, role and counts. Never keys, spend amounts, emails of tracked employees, or key names. The Mac app sends nothing |
| O5 agent access | Small | CSV export through the same policy core. A read-only API token or MCP: justified N/A for v1, revisit when a customer asks |

SOC 2: buyers will ask once companies over about 50 people show up. Not for v1. Do the cheap parts now: audit log, access reviews on the AWS account, a security page, a subprocessor list (AWS, Vercel, Prisma, Stripe, PostShiba), a DPA template, an incident runbook.

---

## 11. Build plan and proof

Small units, each a handful of atomic commits. Billing-affecting and key-holding units ship behind a flag until their proof passes.

| # | Unit | Acceptance check | Rollback |
|---|---|---|---|
| 0 | Spike: Swift worker container decrypts with KMS and polls a mock provider. Check Prisma Postgres roles and RLS. Check Better Auth teams. Check the Fuel Gauge output | A written yes or no for each, with the fallback chosen | Nothing shipped |
| 1 | Scaffold web repo, CI (typecheck, lint, Vitest, build, secret scan), staging and prod separated | CI green on an empty app | Delete the repo |
| 2 | Auth, personal workspace, orgs, roles, teams, invites, the policy core, the two-tenant test fixture | Section 4 matrix and negative tests 1 to 9 and 11 pass | Feature flag off |
| 3 | Audit log | Every mutating policy call writes a row. A test fails if a new mutation doesn't | Revert |
| 4 | Vault: write-only upload, per-org KMS key, split DB roles | Invariants I2, I3, I4, I10 pass in staging | Flag off, delete staged ciphertext |
| 5 | Worker: org totals for all eight providers through KillCordCore, leases, poll log, backoff | Fixture-driven totals match the Mac app's for the same fixtures. Two workers never poll one connection at once | Stop the worker. The app shows stale |
| 6 | Dashboard v0: totals, freshness, every state in section 8 for journeys 1, 2 and 4 | Playwright run of connect, view, key revoked, replace | Revert |
| 7 | Attribution adapters in KillCordCore: Anthropic (analytics cost and usage, users, keys, workspaces), OpenAI (costs, usage, project keys). Verify OpenAI `user_id` on a real org | Fixture tests. Reconciliation: parts plus unassigned equal the total | Flag off, totals still work |
| 8 | Attribution units, assignments, email matching, person and team views, My spend, transparency page | Negative tests 2 and 3. A reassignment does not rewrite history | Flag off |
| 9 | Breakdowns for Google, Vercel, Twilio, Neon | Reconciliation per provider. Neon shows units, never dollars | Per-provider flag |
| 10 | Budgets and alerts, email through PostShiba, test alert | I8. A failed send shows as failed | Disable sending. Alert rows remain |
| 11 | Backfill on connect | 12 months for Anthropic within the provider's request limits, resumable | Flag off |
| 12 | Mac app: sign in, workspace picker, admin key move, My spend, org alerts, copy changes in the same release | The no-account app is byte-for-byte unchanged in behavior. Negative test 8. Offscreen renders only | Sparkle rollback to the prior build |
| 13 | Stripe: trial, plans, portal, entitlements at the policy core, webhooks | Trial, paid, past due, canceled and over-limit states. Duplicate and out-of-order webhooks. I11 | Flag off. Everyone stays on trial |
| 14 | Offboarding checklist, org deletion, export of everything | Negative test 5. I10 for a whole org | Revert |
| 15 | Machine sharing (cuttable) | I6 | Flag off, delete collected readings |
| 16 | Feedback form, analytics events | Payload check: no key, amount or tracked email in any event | Remove the tags |
| 17 | Ops: backups, a real restore into an isolated database, monitoring, runbook, security page, outside review | The restore drill is done by a named person on a named date | n/a |

### Proof per invariant

| | Invariant | Cheapest meaningful proof |
|---|---|---|
| I1 | No tenant reads another's data | Integration suite with two orgs against every route, server action, device endpoint and export. A **route manifest test** fails the build when a new route has no isolation test. RLS underneath if available |
| I2 | A stored key never leaves the cloud | (a) In staging, the web app's identity calling `kms:Decrypt` gets AccessDenied, and its DB role selecting the ciphertext column gets a permission error. (b) **Canary sweep:** seed a fake key with a unique marker, call every endpoint and export as every role, grep every response and the log sink for the marker. (c) The worker exposes no listener: a port scan of the task in CI |
| I3 | A key is never logged | `KeySafetyTests` ported to the worker: hostile responses that echo the key. The canary sweep covers logs |
| I4 | A wrapped key works only for its org and connection | Copy a ciphertext row to another org or connection id: decrypt fails |
| I5 | Removal and demotion take effect on the next request | Negative tests 5, 6, 8 and 11, including with a warm cache |
| I6 | Machine data needs live consent, and equals the preview | One function builds both the preview and the payload (Swift unit test). The server rejects any field outside the schema, and any reading for a member whose sharing is off |
| I7 | Money is exact and reconciles | Decimal strings end to end, Prisma `Decimal`, a lint rule against `number` for money. Property test: parts plus unassigned equal the total |
| I8 | An alert fires once per threshold per period | Worker unit tests on the planner, plus an integration test with two workers and two Macs |
| I9 | Kill Cord never writes to a provider | The worker's HTTP client refuses any method, host or path not on a per-provider allowlist. Test with a write attempt |
| I10 | Delete means deleted | After remove: no ciphertext row, no wrapped data key. After org delete: KMS key in pending deletion |
| I11 | No plan, no polling | A lapsed org's connections are never leased |

---

## 12. Readiness baseline

# Readiness: Kill Cord Teams (collaborative web SaaS + macOS client, spec)
Scope: design only. No repo, no environment, nothing built. November 17, 2026.
Verdict: **unproven** for this scope.

| Requirement | Status | Evidence / limitation | Owner, next step |
|---|---|---|---|
| Brief, journeys, v1 scope | approved | This document. Section 0 decided November 17, 2026 | Unit 0 next |
| Attribution facts | partly verified | Official docs read today. OpenAI `user_id` meaning, OpenAI freshness, Cloudflare endpoint status: unknown | Unit 7 |
| O1 tenant isolation | not assessed, blocking | Nothing built | Unit 2, I1 |
| O1 role matrix and negative tests | not assessed, blocking | Designed only | Unit 2 |
| O3 stored keys never leave, never logged | not assessed, blocking | Designed only | Unit 4, I2 to I4 |
| O3 threat model | drafted | Section 10. No outside review | Unit 17 |
| O3 read-only to providers | not assessed | Holds in the Mac app today. Not built for the worker | Unit 5, I9 |
| Employee machine-data consent | not assessed | Fuel Gauge output unverified | Unit 0, unit 15 |
| O2 feedback | not assessed | Planned. Video is a known gap | Unit 16 |
| O4 analytics payloads | not assessed | Event plan only | Unit 16 |
| O5 agent access | justified N/A | CSV export only in v1. Revisit if asked | n/a |
| Billing states and webhooks | not assessed | Pricing undecided | Decisions 3 to 5, unit 13 |
| Core journeys end to end | not assessed | Nothing built | Units 6, 8, 12 |
| Performance | not assessed | Nothing to measure. Baselines to take at unit 6: dashboard load with 12 months for 50 people, worker cycle time for 100 connections | Unit 6 |
| Accessibility on core journeys | not assessed | | Unit 6 |
| Restore from backup | not assessed, blocking | No database exists | Unit 17 |
| Release and rollback path (web, worker, Mac) | not assessed, blocking | Mac release path exists and works for the free app. Worker path does not exist | Units 1, 5, 12 |
| Monitoring, runbook | not assessed | | Unit 17 |
| Copy changes ("no account", "keys never leave your Mac") in the same release | not assessed | List is in `cloud-migration.md` | Unit 12 |
| Legal: employee-monitoring notice, DPA | not assessed | Needs a lawyer | Before selling outside the US |

## Blockers
None verified, because nothing exists. Four critical controls are not assessed: tenant isolation, key custody, restore, and the worker's release path.

## Unknowns
- OpenAI: what `user_id` identifies, how fresh costs are, whether an Admin key can be read-only. Smallest check: one call on Corey's own org in unit 7.
- Cloudflare: whether the billable-usage endpoint is deprecated. Reread the reference before unit 5.
- Prisma Postgres: custom roles, column grants and RLS. Unit 0.
- Fuel Gauge: machine-readable output. Unit 0.
- Whether small companies will pay. Nothing in this spec measures demand.

## Next step
Unit 0, a spike with fake keys only (#53). The parts that need AWS wait for the account (#51), which is a cloud resource and needs Corey's yes.

---

## Sources (fetched November 17, 2026)

- Anthropic Usage and Cost API (legacy): https://platform.claude.com/docs/en/manage-claude/usage-cost-api
- Anthropic Usage and Cost Analytics API: https://platform.claude.com/docs/en/manage-claude/usage-cost-analytics-api
- Anthropic Claude Code Analytics API: https://platform.claude.com/docs/en/manage-claude/claude-code-analytics-api
- Anthropic Analytics APIs (key types, Enterprise, freshness): https://platform.claude.com/docs/en/manage-claude/analytics-api
- Anthropic Admin API (credentials, roles): https://platform.claude.com/docs/en/manage-claude/admin-api
- Anthropic List API Keys: https://platform.claude.com/docs/en/api/organization/api_keys/list
- Anthropic Spend Limits API (Enterprise): https://platform.claude.com/docs/en/manage-claude/spend-limits-api
- OpenAI Costs: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs/
- OpenAI Usage, completions: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions
- OpenAI project API keys list: https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/api_keys/methods/list
- OpenAI spend limits guide: https://developers.openai.com/api/docs/guides/spend-limits
- OpenAI Admin APIs guide: https://developers.openai.com/api/docs/guides/admin-apis
- Google Cloud Billing export, standard schema: https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/standard-usage
- Vercel FOCUS billing charges: https://vercel.com/docs/rest-api/billing/list-focus-billing-charges (read through search results today, and the adapter header)
- Cloudflare billable usage: https://developers.cloudflare.com/api/resources/billing/subresources/usage/methods/get_account_usage_v1/ (search results today, and the adapter header)
- Cloudflare billing permissions: https://developers.cloudflare.com/billing/understand/billing-permissions/
- Twilio Usage Records: https://www.twilio.com/docs/usage/api/usage-record
- Neon consumption metrics: https://neon.com/docs/guides/consumption-metrics and https://neon.com/docs/reference/api/consumption/get-consumption-history-per-project-v2 (search results today, and the adapter header)
