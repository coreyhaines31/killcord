# Teams worker spike (unit 0)

Throwaway proof for `docs/product/teams-spec.md` unit 0. Not part of the app, not shipped, not linted by the
repo's root SwiftLint run. Findings: `docs/product/spikes/2026-11-unit-0.md`.

- `Sources/TeamsWorkerSpike/Envelope.swift`: AES-256-GCM envelope with a data key per stored key, wrapped by
  a per-org key under an encryption context of org id and connection id. `LocalKeyService` stands in for
  AWS KMS behind two protocols: `DataKeyWrapping` (the web app's `kms:Encrypt`) and `DataKeyUnwrapping`
  (the worker's `kms:Decrypt`).
- `Sources/TeamsWorkerSpike/Worker.swift`: leases due connections with `FOR UPDATE SKIP LOCKED`, decrypts in
  memory, polls through KillCordCore's `OpenAIProvider` and `HTTPClient` (a mock in the spike), writes a
  reading, releases the lease.
- `sql/`: the schema, the split roles with row-level security, and `check-roles.sh`, which proves them.

Run against a throwaway local database (fake keys, throwaway passwords):

```sh
createdb kc_spike
PGHOST=localhost PGDATABASE=kc_spike sql/check-roles.sh      # PGUSER = the database owner
KC_SPIKE_PGHOST=localhost KC_SPIKE_OWNER="$USER" swift test  # without KC_SPIKE_PGHOST only the envelope tests run
swiftlint lint --strict
```

CI runs the same on Linux: `.github/workflows/spikes.yml`.
