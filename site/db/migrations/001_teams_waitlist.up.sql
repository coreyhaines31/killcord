-- Teams waitlist for killcord.app/teams/. Lives in its own schema so the cloud app's
-- Prisma-managed public schema never sees it. Apply as kc_owner; see site/README.md.
BEGIN;

CREATE SCHEMA site;

CREATE TABLE site.teams_waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE CHECK (email = lower(email) AND length(email) <= 254),
  company_size text NOT NULL,
  providers text[] NOT NULL DEFAULT '{}',
  ref text NOT NULL DEFAULT '',
  must_have text NOT NULL DEFAULT '',
  user_agent text NOT NULL DEFAULT '' CHECK (length(user_agent) <= 200),
  -- HMAC of the client IP (never the raw IP), only for the per-IP rate limit.
  ip_hash text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  unsubscribed_at timestamptz,
  welcomed_at timestamptz
);

CREATE INDEX teams_waitlist_ip_hash_updated_at_idx ON site.teams_waitlist (ip_hash, updated_at);
CREATE INDEX teams_waitlist_created_at_idx ON site.teams_waitlist (created_at);

-- The site's function connects as kc_waitlist: read, insert and upsert one table, nothing else.
-- Its password is set out of band (ALTER ROLE kc_waitlist PASSWORD ...), never in this file.
CREATE ROLE kc_waitlist LOGIN NOINHERIT;
GRANT CONNECT ON DATABASE killcord TO kc_waitlist;
GRANT USAGE ON SCHEMA site TO kc_waitlist;
GRANT SELECT, INSERT, UPDATE ON site.teams_waitlist TO kc_waitlist;

COMMIT;
