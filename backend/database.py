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
            video_start_seconds REAL,
            video_end_seconds REAL,
            description TEXT DEFAULT '',
            clip_url TEXT DEFAULT '',
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

        CREATE TABLE IF NOT EXISTS video_analysis_debug_snapshots (
            camera_id INTEGER PRIMARY KEY,
            pet_id INTEGER NOT NULL,
            job_id TEXT DEFAULT '',
            demo_video_name TEXT DEFAULT '',
            demo_video_url TEXT DEFAULT '',
            context_summary TEXT DEFAULT '',
            processing_status TEXT DEFAULT 'completed',
            step_states_json TEXT DEFAULT '[]',
            frames_json TEXT DEFAULT '[]',
            candidate_clips_json TEXT DEFAULT '[]',
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (camera_id) REFERENCES cameras(id),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS video_analysis_jobs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            job_id TEXT NOT NULL UNIQUE,
            camera_id INTEGER NOT NULL,
            pet_id INTEGER NOT NULL,
            status TEXT DEFAULT 'queued',
            error_message TEXT DEFAULT '',
            source_video_path TEXT DEFAULT '',
            source_video_name TEXT DEFAULT '',
            progress_step TEXT DEFAULT 'queued',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            started_at TIMESTAMP,
            completed_at TIMESTAMP,
            FOREIGN KEY (camera_id) REFERENCES cameras(id),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS candidate_clips (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            camera_id INTEGER NOT NULL,
            pet_id INTEGER NOT NULL,
            job_id TEXT NOT NULL,
            rule_id TEXT DEFAULT '',
            primary_rule TEXT DEFAULT '',
            secondary_rules_json TEXT DEFAULT '[]',
            source_video_start_seconds REAL DEFAULT 0,
            source_video_end_seconds REAL DEFAULT 0,
            clip_url TEXT DEFAULT '',
            thumbnail_url TEXT DEFAULT '',
            router_hints_json TEXT DEFAULT '{}',
            analysis_status TEXT DEFAULT 'queued',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (camera_id) REFERENCES cameras(id),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS clip_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            clip_id INTEGER NOT NULL UNIQUE,
            summary TEXT DEFAULT '',
            actions_json TEXT DEFAULT '[]',
            body_state_json TEXT DEFAULT '{}',
            appearance_json TEXT DEFAULT '{}',
            interaction_json TEXT DEFAULT '{}',
            environment_json TEXT DEFAULT '{}',
            mood_hypothesis_json TEXT DEFAULT '{}',
            intent_hypothesis_json TEXT DEFAULT '{}',
            health_signals_json TEXT DEFAULT '[]',
            novelty_signals_json TEXT DEFAULT '[]',
            evidence_json TEXT DEFAULT '{}',
            confidence_json TEXT DEFAULT '{}',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (clip_id) REFERENCES candidate_clips(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS daily_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pet_id INTEGER NOT NULL,
            memory_date TEXT NOT NULL,
            timeline_json TEXT DEFAULT '[]',
            activity_counts_json TEXT DEFAULT '{}',
            daily_summary TEXT DEFAULT '',
            mood_overview_json TEXT DEFAULT '{}',
            health_flags_json TEXT DEFAULT '[]',
            appearance_of_day_json TEXT DEFAULT '{}',
            social_summary_json TEXT DEFAULT '{}',
            change_vs_recent_baseline_json TEXT DEFAULT '{}',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(pet_id, memory_date),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS pet_profile_memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            pet_id INTEGER NOT NULL,
            memory_key TEXT NOT NULL,
            memory_type TEXT DEFAULT '',
            value_json TEXT DEFAULT '{}',
            confidence REAL DEFAULT 0,
            evidence_days INTEGER DEFAULT 0,
            evidence_clips INTEGER DEFAULT 0,
            first_confirmed_at TIMESTAMP,
            last_confirmed_at TIMESTAMP,
            status TEXT DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            UNIQUE(pet_id, memory_key),
            FOREIGN KEY (pet_id) REFERENCES pets(id)
        );

        CREATE TABLE IF NOT EXISTS avatar_generation_jobs (
            job_id TEXT PRIMARY KEY,
            species TEXT DEFAULT 'cat',
            photo_url TEXT DEFAULT '',
            avatar_url TEXT DEFAULT '',
            status TEXT DEFAULT 'queued',
            error_message TEXT DEFAULT '',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_events_pet_id ON events(pet_id);
        CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
        CREATE INDEX IF NOT EXISTS idx_chat_pet_id ON chat_history(pet_id);
        CREATE INDEX IF NOT EXISTS idx_chat_created_at ON chat_history(created_at);
        CREATE INDEX IF NOT EXISTS idx_video_analysis_debug_pet_id ON video_analysis_debug_snapshots(pet_id);
        CREATE INDEX IF NOT EXISTS idx_video_analysis_jobs_camera_id ON video_analysis_jobs(camera_id);
        CREATE INDEX IF NOT EXISTS idx_video_analysis_jobs_pet_id ON video_analysis_jobs(pet_id);
        CREATE INDEX IF NOT EXISTS idx_video_analysis_jobs_status ON video_analysis_jobs(status);
        CREATE INDEX IF NOT EXISTS idx_candidate_clips_camera_id ON candidate_clips(camera_id);
        CREATE INDEX IF NOT EXISTS idx_candidate_clips_pet_id ON candidate_clips(pet_id);
        CREATE INDEX IF NOT EXISTS idx_candidate_clips_job_id ON candidate_clips(job_id);
        CREATE INDEX IF NOT EXISTS idx_daily_memories_pet_date ON daily_memories(pet_id, memory_date);
        CREATE INDEX IF NOT EXISTS idx_pet_profile_memories_pet_id ON pet_profile_memories(pet_id);
        CREATE INDEX IF NOT EXISTS idx_pet_profile_memories_status ON pet_profile_memories(status);
        CREATE INDEX IF NOT EXISTS idx_avatar_generation_jobs_status ON avatar_generation_jobs(status);
        CREATE INDEX IF NOT EXISTS idx_avatar_generation_jobs_created_at ON avatar_generation_jobs(created_at);
    """)

    ensure_column(cursor, "pets", "voice_type", "TEXT DEFAULT 'preset'")
    ensure_column(cursor, "pets", "voice_key", "TEXT DEFAULT 'cat-soft'")
    ensure_column(cursor, "pets", "voice_label", "TEXT DEFAULT '奶呼噜'")
    ensure_column(cursor, "pets", "voice_sample_path", "TEXT DEFAULT ''")
    ensure_column(cursor, "pets", "owner_alias", "TEXT DEFAULT ''")
    ensure_column(cursor, "cameras", "demo_video_path", "TEXT DEFAULT ''")
    ensure_column(cursor, "cameras", "demo_video_name", "TEXT DEFAULT ''")
    ensure_column(cursor, "events", "video_start_seconds", "REAL")
    ensure_column(cursor, "events", "video_end_seconds", "REAL")
    ensure_column(cursor, "events", "clip_url", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "message_type", "TEXT DEFAULT 'text'")
    ensure_column(cursor, "chat_history", "media_kind", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "media_url", "TEXT DEFAULT ''")
    ensure_column(cursor, "chat_history", "trigger_source", "TEXT DEFAULT 'chat'")
    ensure_column(cursor, "video_analysis_debug_snapshots", "job_id", "TEXT DEFAULT ''")
    ensure_column(cursor, "video_analysis_debug_snapshots", "candidate_clips_json", "TEXT DEFAULT '[]'")

    cursor.execute(
        """
        UPDATE video_analysis_jobs
        SET status = 'failed',
            progress_step = 'interrupted',
            error_message = CASE
                WHEN TRIM(error_message) = '' THEN '服务重启导致任务中断'
                ELSE error_message
            END,
            completed_at = CURRENT_TIMESTAMP
        WHERE status IN ('queued', 'running')
        """
    )
    cursor.execute(
        """
        UPDATE video_analysis_debug_snapshots
        SET processing_status = 'failed',
            context_summary = CASE
                WHEN TRIM(context_summary) = '' THEN '服务重启导致分析任务中断'
                ELSE context_summary
            END,
            updated_at = CURRENT_TIMESTAMP
        WHERE processing_status IN ('queued', 'running')
        """
    )

    conn.commit()
    conn.close()
    print("✅ Database initialized successfully")


_VALID_TABLES = {
    "users",
    "pets",
    "cameras",
    "events",
    "chat_history",
    "video_analysis_debug_snapshots",
    "avatar_generation_jobs",
}
_VALID_COLUMN_PATTERNS = {
    "pets": {"voice_type", "voice_key", "voice_label", "voice_sample_path", "owner_alias"},
    "cameras": {"demo_video_path", "demo_video_name"},
    "events": {"video_start_seconds", "video_end_seconds", "clip_url"},
    "chat_history": {"message_type", "media_kind", "media_url", "trigger_source"},
    "video_analysis_debug_snapshots": {"job_id", "candidate_clips_json"},
}

def ensure_column(cursor, table_name, column_name, definition):
    """Add a column if it does not exist yet."""
    if table_name not in _VALID_TABLES:
        raise ValueError(f"Invalid table name: {table_name}")
    allowed = _VALID_COLUMN_PATTERNS.get(table_name, set())
    if column_name not in allowed:
        raise ValueError(f"Invalid column name for {table_name}: {column_name}")
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


def execute_transaction(statements: list[tuple[str, tuple]]):
    """Execute multiple SQL statements in a single transaction."""
    conn = get_db()
    cursor = conn.cursor()
    lastrowid = None
    for query, args in statements:
        cursor.execute(query, args)
        lastrowid = cursor.lastrowid
    conn.commit()
    conn.close()
    return lastrowid


if __name__ == "__main__":
    init_db()
