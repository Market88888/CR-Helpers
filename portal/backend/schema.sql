CREATE TABLE IF NOT EXISTS online_players (
  id_hash TEXT PRIMARY KEY NOT NULL,
  nickname TEXT NOT NULL,
  server_name TEXT NOT NULL,
  last_seen INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_online_expires ON online_players(expires_at);
CREATE INDEX IF NOT EXISTS idx_online_server ON online_players(server_name);

CREATE TABLE IF NOT EXISTS rate_reports (
  id_hash TEXT NOT NULL,
  server_name TEXT NOT NULL,
  vc REAL NOT NULL,
  btc REAL NOT NULL,
  az REAL NOT NULL,
  aarp REAL NOT NULL,
  asc REAL NOT NULL,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (id_hash, server_name)
);

CREATE INDEX IF NOT EXISTS idx_rate_updated ON rate_reports(updated_at);
CREATE INDEX IF NOT EXISTS idx_rate_server ON rate_reports(server_name);

