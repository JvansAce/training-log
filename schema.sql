-- One row per signed-in email. The whole app state lives in the json column;
-- it is small (a year of logging is well under 200 KB) and always read and
-- written as a unit, so there is nothing to gain from splitting it into tables.
CREATE TABLE IF NOT EXISTS state (
  email      TEXT PRIMARY KEY,
  json       TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- One row per signed-in email holding that person's WHOOP OAuth tokens.
-- refresh_token is overwritten on every use: WHOOP rotates it, invalidating
-- the previous one, so the old value is never valid to retry with.
CREATE TABLE IF NOT EXISTS whoop_tokens (
  email         TEXT PRIMARY KEY,
  access_token  TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  expires_at    INTEGER NOT NULL,
  scope         TEXT,
  updated_at    INTEGER NOT NULL
);

-- Short-lived row proving an /api/whoop/authorize redirect actually came
-- from this app, and which signed-in email it belongs to. Deleted the
-- moment /api/whoop/callback consumes it, or after 10 minutes, whichever
-- comes first.
CREATE TABLE IF NOT EXISTS whoop_oauth_state (
  state      TEXT PRIMARY KEY,
  email      TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
