# Releasing

For maintainers. Releases are cut from `main`. Run it from a separate worktree (`git worktree add ../killcord-release main`) so work in progress can't leak into the build.

```sh
git checkout main && git pull
NOTARY_PROFILE=<your-notary-profile> Scripts/release.sh 0.1.0
```

`Scripts/release.sh` is a skeleton modeled on Fuel Gauge's and hasn't been run for Kill Cord yet. It:

1. Runs the KillCordCore tests.
2. Archives the app and exports it with Developer ID signing (cloud-managed, so no certificate lives on the machine).
3. Notarizes and staples the app, builds the DMG, and notarizes and staples that.
4. Checks the app inside the DMG with Gatekeeper.
5. Signs the update with Sparkle and writes `appcast.xml`.
6. Publishes a GitHub release `v<version>` with the DMG, an unversioned `KillCord.dmg`, and `appcast.xml`.
7. Bumps the version and checksum in the Homebrew cask.

The build number is the commit count, so it always goes up.

## Before the first release

- **Sparkle key.** `SUPublicEDKey` in `project.yml` (and `KillCord/Info.plist`) is a placeholder, and the script refuses to run until it's replaced. Generate a key pair with Sparkle's `generate_keys --account killcord`, which keeps the private key in the login keychain, and paste the public key into both files. Until then the app doesn't start Sparkle at all.
- **Bundle ID.** `app.killcord.KillCord`. It names the Keychain service (`app.killcord.KillCord.providers`) and the preferences file, so changing it after release orphans people's saved keys.
- **Architectures.** The project builds Xcode's default (universal on a release archive). Decide whether to ship Apple silicon only.
- **Cask.** `Scripts/homebrew/killcord.rb` is copied into [coreyhaines31/homebrew-tap](https://github.com/coreyhaines31/homebrew-tap) on the first release.

## One-time setup

- **Xcode:** signed in to the team in Settings › Accounts, or `ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID` for an App Store Connect API key.
- **Notarization:** a notarytool keychain profile (`xcrun notarytool store-credentials <name>`), passed as `NOTARY_PROFILE`. Or `APPLE_ID` and `APPLE_APP_PASSWORD` in the environment.
- **Sparkle key:** the EdDSA private key in the login keychain under the account `killcord`. The script passes `--account killcord`, so another app's key is never used. For CI, put the private key in `SPARKLE_KEY_FILE`.
- **GitHub CLI:** `gh` signed in with push access to this repo and the tap.

## Updates

The app checks `https://github.com/coreyhaines31/killcord/releases/latest/download/appcast.xml` (`SUFeedURL` in `project.yml`). Each release's appcast points at that release's DMG.

## CI

`.github/workflows/ci.yml` runs the KillCordCore tests on Linux for every pull request. The macOS lint, build, and test job runs only when started by hand (Actions › CI › Run workflow) while the repository is private, because private macOS runners bill at 10x. Run it before each release.

## When something goes wrong

- **notarytool hangs on "initiating connection":** if no entry shows in `xcrun notarytool history` after about 5 minutes, stop it and run the script again. Nothing is published before notarization finishes.
- **GitHub returns a 500 and leaves a draft:** `gh release edit v<version> --draft=false --latest`, then bump the cask by hand.
- **The cask push is rejected:** another release pushed first. Redo the cask bump in a fresh clone of the tap.
- **Release notes:** the script uses `--generate-notes`. Rewrite them by hand for people, not commits.
