# Kill Cord Teams in the Mac app (preview flag)

Unit 12 groundwork for Kill Cord Teams (`teams-spec.md`, section 11).

**Off by default.** With the flag off, the free, no-account app behaves exactly as before:
- no Teams tab in Settings
- no Teams session is built
- no request to any Teams host

Tests check each of these: `TeamsFlagOffTests` in KillCordCore and `TeamsTabTests` in the app's settings tests. There is no switch in the app.

## Turning it on (development only)

```sh
defaults write app.killcord.KillCord teamsEnabled -bool true
# Optional: point at a local killcord-cloud (plain http is allowed only for localhost and 127.0.0.1)
defaults write app.killcord.KillCord teamsBaseURL "http://localhost:3000"
# Off again
defaults delete app.killcord.KillCord teamsEnabled
```

The default host, `https://app.killcord.app`, is not live yet.

## What it does

A "Teams (preview)" Settings tab offers three things:
- **Sign in:** a device code, approved in the browser at `/device` (killcord-cloud PR #30).
- **Workspace picker.**
- **My spend** for the chosen workspace.

Details:
- **Token storage:** the device token lives in the Keychain under `app.killcord.teams.device-token`, which can't collide with a connection's UUID account.
- **Token handling:** it is sent only in the Authorization header and never appears in an error.
- **Sign out:** revokes the token on the server and deletes it locally even when the server can't be reached.
- **Not here:** moving provider keys to the cloud waits for the vault (unit 4). Nothing about this Mac's connections is sent.
