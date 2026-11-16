# Contributing

Bug reports, ideas, and pull requests are welcome. Open an issue first for anything bigger than a small fix, so we can agree on the approach before you spend time on it.

**Never put a real API key, token, or service account key in an issue, a pull request, a test, or a screenshot.** Tests use fake keys like `sk-ant-admin01-TEST-…`.

## Reporting a bug

[Open an issue](https://github.com/coreyhaines31/killcord/issues/new/choose) and include:

- Your Kill Cord version (Settings › General) and macOS version.
- Which provider it's about.
- What you did, what you expected, and what happened. A screenshot of the panel helps (check it shows no key).

For a number that looks wrong, include what Kill Cord showed, what the provider's console showed for the same day or month, and the "Last checked" time.

## Setting up

Follow [Building from source](README.md#building-from-source) in the README. In short:

```sh
brew install xcodegen swiftlint
xcodegen generate
xcodebuild -project KillCord.xcodeproj -scheme KillCord \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

`KillCord.xcodeproj` is generated from `project.yml` and isn't checked in. Add new files on disk and run `xcodegen generate` again.

Most logic lives in `Packages/KillCordCore`, which has no AppKit and builds and tests on macOS and Linux:

```sh
cd Packages/KillCordCore && swift test
```

## Adding or changing a provider

Each adapter in `Packages/KillCordCore/Sources/KillCordCore/Providers/` uses one provider's official billing or usage API, with the doc links at the top of the file. When you change one:

- Check the endpoint, auth, parameters, pagination, and response shape against the provider's current docs, and update the links.
- Add a fixture in `Tests/KillCordCoreTests/Fixtures` built from the documented response, and tests for the request and the parsing.
- Money is `Decimal`, never `Double`. Say plainly when a provider reports usage instead of dollars, or nothing at all. Never show an estimate without labeling it.
- Add or update the provider's entries in `CapsCatalog.swift`, with console links taken from the provider's docs.

## Ground rules

These keep Kill Cord something people can trust with billing keys:

- **Keys stay in the Keychain.** Never in files, UserDefaults, logs, error messages, or exports. Error text is built from fixed strings, and tests check that no key appears in any of it.
- **Read only.** Kill Cord reads billing data. It never changes a provider setting, and it asks for the narrowest key each provider offers.
- **No telemetry.** The only network requests are to the providers' billing APIs and Sparkle's update check.
- **Honest freshness.** Show when each number was last checked, mark anything read before sleep or while offline as not live, and show each provider's documented lag.

## Before you open a pull request

- Run the tests and `swiftlint --strict`.
- Keep each pull request to one change, in small commits.
- For a change you can see, add a before-and-after screenshot (with sample data: debug builds take `--demo`).

## Contributor terms

Kill Cord is licensed under FSL-1.1-MIT, and some future features may be sold under a commercial license. To keep that possible, every contribution comes with these terms. By opening a pull request, you agree that:

1. You wrote the contribution, or otherwise have the right to submit it.
2. You grant Corey Haines a perpetual, worldwide, non-exclusive, royalty-free, irrevocable license to use, modify, and distribute your contribution, and to sublicense and relicense it under any terms, including commercial ones.
3. You keep the copyright in your contribution, and you can use it however you like.

If you can't agree to these terms, please open an issue describing the change instead.
