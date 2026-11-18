#!/bin/bash
# Proves the role split and RLS on a throwaway database. Exit code 0 only when every check behaves.
# Env: PGHOST, PGPORT, PGDATABASE, and PGUSER (the owner). Never point this at a real database.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
pass=0
fail=0

owner() { PGOPTIONS="-c client_min_messages=warning" psql -v ON_ERROR_STOP=1 -qAtX "$@"; }
as_role() {
    local role=$1; shift
    PGPASSWORD=spike-only-not-real psql -qAtX -U "$role" -h "${PGHOST:-localhost}" -c "$1" 2>&1
}
expect() {
    local label=$1 want=$2 got=$3
    if [[ "$got" == *"$want"* ]]; then
        echo "ok    $label"; pass=$((pass + 1))
    else
        echo "FAIL  $label: wanted '$want', got '$got'"; fail=$((fail + 1))
    fi
}

owner -f "$here/schema.sql" >/dev/null
owner -f "$here/roles.sql" >/dev/null
owner <<'SQL' >/dev/null
INSERT INTO orgs VALUES ('aaaaaaaa-0000-0000-0000-000000000001', 'Org A'), ('bbbbbbbb-0000-0000-0000-000000000002', 'Org B');
INSERT INTO users VALUES ('11111111-0000-0000-0000-000000000001', 'a@example.com');
INSERT INTO sessions VALUES ('22222222-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'tok-TEST');
INSERT INTO connections (id, org_id, provider, key_ciphertext, wrapped_data_key) VALUES
  ('cccccccc-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-000000000001', 'openai', '\x01', '\x02'),
  ('cccccccc-0000-0000-0000-00000000000b', 'bbbbbbbb-0000-0000-0000-000000000002', 'openai', '\x03', '\x04');
SQL

A="SET app.org_id = 'aaaaaaaa-0000-0000-0000-000000000001';"
B_ID="bbbbbbbb-0000-0000-0000-000000000002"

expect "web reads its own org's connections, not another's" \
    "cccccccc-0000-0000-0000-00000000000a" "$(as_role kc_spike_web "$A SELECT id FROM connections")"
expect "web sees exactly one row under RLS" "1" "$(as_role kc_spike_web "$A SELECT count(*) FROM connections")"
expect "web with no org set sees nothing" "0" "$(as_role kc_spike_web "SELECT count(*) FROM connections")"
expect "web cannot SELECT key_ciphertext" "permission denied" \
    "$(as_role kc_spike_web "$A SELECT key_ciphertext FROM connections")"
expect "web cannot SELECT * (includes ciphertext)" "permission denied" \
    "$(as_role kc_spike_web "$A SELECT * FROM connections")"
expect "web cannot read ciphertext back through RETURNING" "permission denied" \
    "$(as_role kc_spike_web "$A UPDATE connections SET key_ciphertext = '\x09' RETURNING key_ciphertext")"
as_role kc_spike_web "$A UPDATE connections SET key_ciphertext = '\\x09' WHERE id = 'cccccccc-0000-0000-0000-00000000000a'" >/dev/null
expect "web can replace its own org's key (write-only)" "1" \
    "$(owner -c "SELECT count(*) FROM connections WHERE key_ciphertext = '\\x09'")"
expect "web cannot insert a connection into another org" "row-level security" \
    "$(as_role kc_spike_web "$A INSERT INTO connections (id, org_id, provider, key_ciphertext, wrapped_data_key) VALUES (gen_random_uuid(), '$B_ID', 'openai', '\x05', '\x06')")"
as_role kc_spike_web "$A UPDATE connections SET key_ciphertext = '\\x07' WHERE id = 'cccccccc-0000-0000-0000-00000000000b'" >/dev/null
expect "web cannot change another org's key" "0" \
    "$(owner -c "SELECT count(*) FROM connections WHERE key_ciphertext = '\\x07'")"
expect "worker cannot read users" "permission denied" "$(as_role kc_spike_worker "SELECT email FROM users")"
expect "worker cannot read sessions" "permission denied" "$(as_role kc_spike_worker "SELECT token FROM sessions")"
expect "worker cannot read orgs" "permission denied" "$(as_role kc_spike_worker "SELECT name FROM orgs")"
expect "worker reads ciphertext for every org" "2" \
    "$(as_role kc_spike_worker "SELECT count(key_ciphertext) FROM connections")"
expect "worker cannot rewrite a stored key" "permission denied" \
    "$(as_role kc_spike_worker "UPDATE connections SET key_ciphertext = '\x08'")"
expect "worker can take a lease with FOR UPDATE SKIP LOCKED" "cccccccc" \
    "$(as_role kc_spike_worker "UPDATE connections SET lease_owner = 'w1' WHERE id IN (SELECT id FROM connections ORDER BY id LIMIT 1 FOR UPDATE SKIP LOCKED) RETURNING id")"
expect "worker cannot delete connections" "permission denied" "$(as_role kc_spike_worker "DELETE FROM connections")"

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
