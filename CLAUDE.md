# Kill Cord

A free, source-available (FSL-1.1-MIT) macOS menu bar app that shows today's and month-to-date API spend across usage-billed providers, and walks people through turning on each provider's native spend caps. The product spec is `docs/product/spec.md`.

## Build and test

```sh
# Core: no AppKit, builds and tests on macOS and Linux
cd Packages/KillCordCore && swift build && swift test
swift run killcord-dev          # prints the caps catalog and sample data; no keys, no network

# App (macOS only)
brew install xcodegen swiftlint
xcodegen generate               # KillCord.xcodeproj is generated, never committed
xcodebuild -project KillCord.xcodeproj -scheme KillCord -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO test
swiftlint --strict
open "build/DerivedData/Build/Products/Debug/Kill Cord.app" --args --demo   # labeled sample data
```

## Architecture

- `project.yml`: XcodeGen. Target `KillCord`, product "Kill Cord", bundle id `app.killcord.KillCord`, macOS 14, Swift 6, hardened runtime, Sparkle 2. PanelKit 0.2.1 supplies the Brushed panel. The Sparkle public key is configured; its private key stays in the login Keychain.
- `Packages/KillCordCore` (SwiftPM library, plus `killcord-dev`):
  - `Money.swift`: `Money`, `MoneyTotals`, `MoneyText`. Always `Decimal`.
  - `Provider.swift`: `ProviderID`, `ProviderInfo` (capability, credential fields, key-power warning, lag, billing time zone, minimum refresh interval).
  - `Credentials.swift`: `SecretStore` protocol, `InMemorySecretStore`, `ProviderCredentials` (redacted descriptions), `CredentialStore` (one Keychain item per provider), `Redactor`. `KeychainSecretStore.swift` is behind `#if canImport(Security)`.
  - `HTTP.swift`: `HTTPClient` protocol, `URLSessionHTTPClient` (ephemeral), `MockHTTPClient`.
  - `SpendError.swift`: the error taxonomy; messages are fixed text and never include a key.
  - `SpendProvider.swift`: the adapter protocol, `SpendSnapshot`, `BillingWindow`, `CapVerification`.
  - `Providers/`: one adapter per provider, doc URLs at the top of each file. Google adds `GoogleAuth.swift` (service account JWT, pluggable `RS256Signer`).
  - `Freshness.swift`, `RefreshScheduler.swift`, `ThresholdPlanner.swift`, `SpendSummary.swift`: freshness and stale-after-sleep, polling with backoff, once-per-period alerts, totals.
  - `CapsCatalog.swift`: every provider's native caps (one data file) and `CapAuditState`.
  - `SpendText.swift`, `DemoData.swift`.
- `KillCord/` (app): `App/` (delegate, status item, glyph, preferences, demo mode), `Model/` (`SpendModel`, `Alerts`), `Panel/`, `Settings/` (Providers, Alerts, Caps Audit, General), `Updates/`.

## Rules

- **Keys only in the Keychain.** Never in files, UserDefaults, logs, error messages, exports, or test fixtures. Use fake keys in tests (`sk-ant-admin01-TEST-…`). Don't read real credential files.
- **Read only, least privilege.** Kill Cord never changes provider settings. Say plainly when a provider has no read-only key.
- **Network:** only provider billing APIs and Sparkle. No telemetry, analytics, or accounts.
- **Honesty:** money is `Decimal`. Model providers without a dollar API with `SpendCapability` (`.usageUnitsOnly`, `.noUsageAPI`, `.requiresSetup`). Never show an estimate without labeling it. Show last-checked time and provider lag; after sleep or offline, say "not live". Never imply overnight coverage.
- **Verify provider APIs** against official docs before changing an adapter, and keep the doc links current. Console links in the caps catalog come from the providers' docs; a wrong link is worse than none.
- **Copy:** no em dashes anywhere user-facing. Use commas, colons, or parentheses. No personal information in the repo.
- **Out of v1:** the paid always-on monitor and auto-stop. At most a quiet "Always-on monitoring (coming later)" line.
- **Git:** small atomic commits with descriptive messages. Feature branches; don't push or open PRs unless asked.
- **CI:** Core tests on Linux and the full macOS build on every push and pull request (the repo is public, so macOS runners are free).
