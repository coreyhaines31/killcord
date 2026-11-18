-- Two login roles with split privileges, plus row-level security. Run as the owner after schema.sql.
-- Passwords here are throwaway values for a local or CI database, never a real one.
DO $$ BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kc_spike_web') THEN
        CREATE ROLE kc_spike_web LOGIN PASSWORD 'spike-only-not-real';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'kc_spike_worker') THEN
        CREATE ROLE kc_spike_worker LOGIN PASSWORD 'spike-only-not-real';
    END IF;
END $$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM kc_spike_web, kc_spike_worker;
GRANT USAGE ON SCHEMA public TO kc_spike_web, kc_spike_worker;

-- Web: people and orgs; connections it can create, replace and delete but never read the key columns of.
GRANT SELECT, INSERT, UPDATE, DELETE ON orgs, users, sessions TO kc_spike_web;
GRANT SELECT (id, org_id, provider, next_poll_at, last_error) ON connections TO kc_spike_web;
GRANT INSERT (id, org_id, provider, key_ciphertext, wrapped_data_key) ON connections TO kc_spike_web;
GRANT UPDATE (key_ciphertext, wrapped_data_key) ON connections TO kc_spike_web;
GRANT DELETE ON connections TO kc_spike_web;
GRANT SELECT ON spend_readings TO kc_spike_web;

-- Worker: connections (including ciphertext) and the lease columns, readings to write. No people, no orgs.
GRANT SELECT ON connections TO kc_spike_worker;
GRANT UPDATE (next_poll_at, lease_owner, lease_until, last_error) ON connections TO kc_spike_worker;
GRANT INSERT ON spend_readings TO kc_spike_worker;
GRANT USAGE ON SEQUENCE spend_readings_id_seq TO kc_spike_worker;

-- Row-level security: the web role sees one org at a time, set per request with
-- SET LOCAL app.org_id. The worker polls every org.
ALTER TABLE connections ENABLE ROW LEVEL SECURITY;
ALTER TABLE spend_readings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS web_one_org ON connections;
DROP POLICY IF EXISTS worker_all ON connections;
DROP POLICY IF EXISTS web_one_org ON spend_readings;
DROP POLICY IF EXISTS worker_all ON spend_readings;
CREATE POLICY web_one_org ON connections TO kc_spike_web
    USING (org_id = nullif(current_setting('app.org_id', true), '')::uuid)
    WITH CHECK (org_id = nullif(current_setting('app.org_id', true), '')::uuid);
CREATE POLICY worker_all ON connections TO kc_spike_worker USING (true) WITH CHECK (true);
CREATE POLICY web_one_org ON spend_readings TO kc_spike_web
    USING (org_id = nullif(current_setting('app.org_id', true), '')::uuid);
CREATE POLICY worker_all ON spend_readings TO kc_spike_worker USING (true) WITH CHECK (true);
