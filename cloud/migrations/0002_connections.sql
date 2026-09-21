CREATE TABLE consent_requests(id TEXT PRIMARY KEY, request_json TEXT NOT NULL, user_id TEXT, expires_at INTEGER NOT NULL, used INTEGER NOT NULL DEFAULT 0);
CREATE TABLE connections(id TEXT PRIMARY KEY, user_id TEXT NOT NULL, client_id TEXT NOT NULL, device_ids TEXT NOT NULL, actions TEXT NOT NULL, created_at TEXT NOT NULL, revoked_at TEXT);
CREATE INDEX connections_user ON connections(user_id);
