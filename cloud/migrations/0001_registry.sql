CREATE TABLE devices(id TEXT PRIMARY KEY,user_id TEXT,kind TEXT NOT NULL,name TEXT NOT NULL,agent_version TEXT NOT NULL,last_seen TEXT,created_at TEXT NOT NULL,revoked_at TEXT);
CREATE INDEX devices_user ON devices(user_id);
CREATE TABLE tokens(token_hash TEXT PRIMARY KEY,device_id TEXT NOT NULL,created_at TEXT NOT NULL,revoked_at TEXT);
CREATE INDEX tokens_device ON tokens(device_id);
CREATE TABLE pairing(code TEXT PRIMARY KEY,device_id TEXT NOT NULL,bootstrap_hash TEXT UNIQUE NOT NULL,deadline INTEGER NOT NULL,claimed_at TEXT,redeemed_hash TEXT);
CREATE INDEX pairing_deadline ON pairing(deadline);
CREATE TABLE deleting(user_id TEXT PRIMARY KEY);
