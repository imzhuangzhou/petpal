import sqlite3
import os
from datetime import datetime

DB_PATH = os.path.join(os.path.dirname(__file__), "petpal.db")


def get_db():
    """Get a database connection."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db():
    """Initialize database tables."""
    conn = get_db()
    cursor = conn.cursor()

    cursor.executescript("""
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nickname TEXT NOT NULL,
            avatar_url TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS pets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            breed TEXT DEFAULT '',
            species TEXT DEFAULT 'cat',
            photo_url TEXT DEFAULT '',
            avatar_url TEXT DEFAULT '',
            language_style TEXT DEFAULT 'tsundere',
            style_prompt TEXT DEFAULT '',
            owner_alias TEXT DEFAULT '',
            voice_type TEXT DEFAULT 'preset',
            voice_key TEXT DEFAULT 'cat-soft',
            voice_label TEXT DEFAULT '奶呼噜',
            voice_sample_path TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS cameras (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT DEFAULT '客厅',
            stream_url TEXT DEFAULT '',
            is_demo INTEGER DEFAULT 0,
            status TEXT DEFAULT 'disconnected',
            demo_video_path TEXT DEFAULT '',
            demo_video_name TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id)
        );

        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            camera_id INTEGER,
            pet_id INTEGER,
            timestamp TIMESTAMP NOT NULL,
            event_type TEXT NOT NULL,
            duration_seconds REAL DEFAULT 0,
            description TEXT DEFAULT '',
            frame_path TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (camera_id) REFERENCES cameras(id),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS chat_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pet_id INTEGER NOT NULL,
            role TEXT NOT NULL,
            content TEXT NOT NULL,
            image_url TEXT DEFAULT '',
            message_type TEXT DEFAULT 'text',
            media_kind TEXT DEFAULT '',
            media_url TEXT DEFAULT '',
            trigger_source TEXT DEFAULT 'chat',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE INDEX IF NOT EXISTS idx_events_pet_id ON events(pet_id);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
        CREATE INDEX IF NOT EXISTS idx_chat_pet_id ON chat_history(pet_id);
    """)

    ensure_column(cursor, "pets", "voice_type", "TEXT DEFAULT 'preset'")
    ensure_column(cursor, "pets", "voice_key", "TEXT DEFAULT 'cat-soft'")
    ensure_column(cursor, "pets", "voice_label", "TEXT DEFAULT '奶呼噜'")
    ensure_column(cursor, "pets", "voice_sample_path", "TEXT DEFAULT ''")
    ensure_column(cursor, "pets", "owner_alias", "TEXT DEFAULT ''")
    ensure_column(cursor, "cameras", "demo_video_path", "TEXT DEFAULT ''")
    ensure_column(cursor, "cameras", "demo_video_name", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "message_type", "TEXT DEFAULT 'text'")
    ensure_column(cursor, "chat_history", "media_kind", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "media_url", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "trigger_source", "TEXT DEFAULT 'chat'")

    conn.commit()
    conn.close()
    print("✅ Database initialized successfully")


def ensure_column(cursor, table_name, column_name, definition):
    """Add a column if it does not exist yet."""
    columns = {
        row["name"]
        for row in cursor.execute(f"PRAGMA table_info({table_name})").fetchall()
    }
    if column_name not in columns:
        cursor.execute(
            f"ALTER TABLE {table_name} ADD COLUMN {column_name} {definition}"
        )


def query_db(query, args=(), one=False):
    """Query helper that returns dicts."""
    conn = get_db()
    cursor = conn.execute(query, args)
    rows = cursor.fetchall()
    conn.close()
    if one:
        return dict(rows[0]) if rows else None
    return [dict(row) for row in rows]


def execute_db(query, args=()):
    """Execute an INSERT/UPDATE/DELETE and return lastrowid."""
    conn = get_db()
    cursor = conn.execute(query, args)
    conn.commit()
    lastrowid = cursor.lastrowid
    conn.close()
    return lastrowid


if __name__ == "__main__":
    init_db()
