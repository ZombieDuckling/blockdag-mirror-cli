"""
Simple state management for the BlockDAG mirror program.

This module manages a SQLite database that tracks repository mirror state
(e.g. last mirrored SHA and last sync time).  The database can be used to
detect drift or avoid unnecessary pushes.

NOTE: This is a minimal implementation. You can extend it to store
additional metadata such as visibility, default branch, archived status,
etc.  For more complex needs consider using SQLAlchemy or another ORM.
"""
import sqlite3
from pathlib import Path
from datetime import datetime


DB_PATH = Path(".mirror_state.sqlite")


def init_db():
    """Initialise the SQLite database and create the required table if needed.

    Returns:
        sqlite3.Connection: A connection to the database.
    """
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute(
        """
        CREATE TABLE IF NOT EXISTS repos (
            name TEXT PRIMARY KEY,
            last_sha TEXT,
            last_sync_at TEXT
        )
        """
    )
    conn.commit()
    return conn


def update_repo(conn: sqlite3.Connection, name: str, sha: str):
    """Insert or update the state entry for a repository.

    Args:
        conn: SQLite connection returned from init_db.
        name: Repository name.
        sha: Latest commit SHA mirrored to destinations.
    """
    c = conn.cursor()
    now = datetime.utcnow().isoformat()
    c.execute(
        "INSERT OR REPLACE INTO repos (name, last_sha, last_sync_at) VALUES (?, ?, ?)",
        (name, sha, now),
    )
    conn.commit()


def get_repo_state(conn: sqlite3.Connection, name: str):
    """Retrieve state information for a repository.

    Args:
        conn: SQLite connection.
        name: Repository name.

    Returns:
        tuple[str, str] | None: (last_sha, last_sync_at) or None if not found.
    """
    c = conn.cursor()
    c.execute("SELECT last_sha, last_sync_at FROM repos WHERE name = ?", (name,))
    row = c.fetchone()
    return row if row else None
