# Niche paid services: balances, more adapters, custom and manual connections

Status: building (2026-11-17). Research: `site/data/services.json` and the niche-services research notes.

## Brief

- **Audience:** people already using Kill Cord for API spend who also pay small, metered services (SEO data,
  scraping, agent wallets, email verification). Today they check each dashboard by hand, or find out when a
  call fails because the balance hit zero.
- **Job:** see what's left on each service next to API spend, and get one alert before it runs out.
- **Useful outcome:** every paid service they rely on is on the panel, with an honest label for how Kill Cord
  knows the number: read live from the service, read from an endpoint they set up, or typed in by them.
- **Better-model test:** not an AI feature. The product's value is the read-only connections and honest labels.

Platform profile: local macOS menu bar app, single user, no backend. Orgs, feedback, analytics and agent
access stay justified N/A, as in `spec.md`.

## Units

| # | Unit | Acceptance check | Rollback |
|---|---|---|---|
| 0 | Migration treats an unreadable connection item as unknown (#38) | Test with a store that throws on one UUID read: nothing written, retried next launch | Revert PR |
| 1 | Balance reading kind (#58) | Balance never adds into totals; low-balance alert fires once per crossing, re-arms after a top-up, survives a failed read; old caches decode; renders show it | Revert PR; old caches still decode |
| 2 | Built-in adapters: DataForSEO, treg, Monid, OpenRouter, Firecrawl, Ahrefs (#59) | Fixture tests per adapter (fake data), 4xx detail redacted, KeySafetyTests cover each, only GET to the documented host | Remove the provider cases |
| 3 | Custom connection (#60) | https only, no cross-host redirect, size cap, timeout, private and loopback hosts refused, secret never in errors; JSON path and scale parsing tested | Remove the custom case |
| 4 | Manual tracking (#61) | Shown as "Not live: entered by you", never in totals, renewal reminder fires once per renewal | Remove the manual case |
| 5 | Site dataset and docs (#62) | `services.json` tiers match what shipped; no deploy | Revert PR |

## States (balance)

| State | What shows |
|---|---|
| Not read yet | "Balance: Not read yet" |
| Live | "$12.40 left" or "8,200 of 10,000 credits left", details below (used, deposited, reset, labeled estimate) |
| Stale | Same figure, with the existing "not live" line and reason |
| Failed | Existing inline error with the provider's redacted message |
| Low | One notification per crossing: "DataForSEO is down to $4.20" |

## Honesty rules

- A balance is what's left, not spend. It never adds into today's or this month's totals, and the panel says so.
- Credits are converted to dollars only with a known rate, always labeled "(estimate)".
- Custom connections say Kill Cord can't verify the numbers. Manual entries say "Not live: entered by you".
