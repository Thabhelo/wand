"""Persistence boundary. Handlers depend on Repository, not SQLite queries."""
import json
import sqlite3
from typing import Protocol

class Repository(Protocol):
    def put(self, collection: str, key: str, value: dict): ...
    def get(self, collection: str, key: str) -> dict | None: ...
    def values(self, collection: str) -> list[dict]: ...
    def delete(self, collection: str, key: str): ...
    def close(self): ...

class SQLiteRepository:
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('CREATE TABLE IF NOT EXISTS records (collection TEXT, key TEXT, value TEXT NOT NULL, PRIMARY KEY(collection,key))')
        self.db.commit()
    def put(self, collection, key, value):
        if collection == 'audit' and self.get(collection, key):
            raise ValueError('Audit records cannot be updated')
        self.db.execute('INSERT OR REPLACE INTO records VALUES (?,?,?)', (collection, key, json.dumps(value)))
        self.db.commit()
    def get(self, collection, key):
        row = self.db.execute('SELECT value FROM records WHERE collection=? AND key=?', (collection, key)).fetchone()
        return json.loads(row[0]) if row else None
    def values(self, collection):
        return [json.loads(r[0]) for r in self.db.execute('SELECT value FROM records WHERE collection=?', (collection,))]
    def delete(self, collection, key):
        self.db.execute('DELETE FROM records WHERE collection=? AND key=?', (collection,key))
        self.db.commit()
    def close(self):
        self.db.close()
