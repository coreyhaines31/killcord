-- Kill Cord Teams unit 0 spike. Run as the database owner on a throwaway database.
DROP TABLE IF EXISTS spend_readings, connections, sessions, users, orgs CASCADE;

CREATE TABLE orgs (id uuid PRIMARY KEY, name text NOT NULL);
CREATE TABLE users (id uuid PRIMARY KEY, email text NOT NULL);
CREATE TABLE sessions (id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users, token text NOT NULL);

CREATE TABLE connections (
    id uuid PRIMARY KEY,
    org_id uuid NOT NULL REFERENCES orgs,
    provider text NOT NULL,
    key_ciphertext bytea NOT NULL,
    wrapped_data_key bytea NOT NULL,
    next_poll_at timestamptz NOT NULL DEFAULT now(),
    lease_owner text,
    lease_until timestamptz,
    last_error text
);
CREATE INDEX connections_org_id ON connections (org_id);
CREATE INDEX connections_due ON connections (next_poll_at);

CREATE TABLE spend_readings (
    id bigserial PRIMARY KEY,
    connection_id uuid NOT NULL REFERENCES connections ON DELETE CASCADE,
    org_id uuid NOT NULL REFERENCES orgs,
    month numeric,
    today numeric,
    fetched_at timestamptz NOT NULL,
    worker text NOT NULL
);
CREATE INDEX spend_readings_connection_id ON spend_readings (connection_id);
CREATE INDEX spend_readings_org_id ON spend_readings (org_id);
