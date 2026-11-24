-- Reverts 001_teams_waitlist.up.sql. Drops every signup: export them first.
BEGIN;

REVOKE ALL ON site.teams_waitlist FROM kc_waitlist;
REVOKE ALL ON SCHEMA site FROM kc_waitlist;
REVOKE CONNECT ON DATABASE killcord FROM kc_waitlist;
DROP ROLE kc_waitlist;
DROP TABLE site.teams_waitlist;
DROP SCHEMA site;

COMMIT;
