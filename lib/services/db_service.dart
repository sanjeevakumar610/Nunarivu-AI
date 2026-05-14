import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Singleton SQLite wrapper.
///
/// Schema history:
///   v1 — profiles, pdfs, messages
///   v2 — chats table
///   v3 — profile language/age/grade/instructions columns + feedback table
///   v4 — reply_length column on profiles
///   v5 — ai_persona column on profiles
///   v6 — reminders table + badges table
///   v7 — pdf_chunks table (page-aware RAG embeddings)
class DbService {
  DbService._();
  static final DbService instance = DbService._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'nunarivu.db');
    return openDatabase(
      path,
      version: 7,
      onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // ── Full schema (fresh install) ──────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE profiles (
        id                  TEXT PRIMARY KEY,
        name                TEXT NOT NULL,
        avatar_seed         INTEGER NOT NULL,
        created_at          INTEGER NOT NULL,
        last_used_at        INTEGER NOT NULL,
        lang_tamil          INTEGER NOT NULL DEFAULT 1,
        lang_english        INTEGER NOT NULL DEFAULT 1,
        age_group           TEXT NOT NULL DEFAULT 'school',
        age                 INTEGER,
        school_name         TEXT,
        grade               TEXT,
        instr_examples      INTEGER NOT NULL DEFAULT 0,
        instr_disability    INTEGER NOT NULL DEFAULT 0,
        custom_instructions TEXT,
        reply_length        TEXT,
        ai_persona          TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE pdfs (
        id              TEXT PRIMARY KEY,
        profile_id      TEXT NOT NULL,
        file_path       TEXT NOT NULL,
        title           TEXT NOT NULL,
        extracted_text  TEXT NOT NULL,
        page_count      INTEGER NOT NULL,
        created_at      INTEGER NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id           TEXT PRIMARY KEY,
        chat_id      TEXT,
        profile_id   TEXT NOT NULL,
        role         TEXT NOT NULL,
        text         TEXT NOT NULL,
        image_path   TEXT,
        pdf_id       TEXT,
        created_at   INTEGER NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE,
        FOREIGN KEY (pdf_id)     REFERENCES pdfs(id)     ON DELETE SET NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_messages_profile ON messages(profile_id, created_at)');
    await db.execute(
        'CREATE INDEX idx_pdfs_profile ON pdfs(profile_id, created_at)');

    await _createChatsTable(db);
    await _createFeedbackTable(db);
    await _createRemindersTable(db);
    await _createBadgesTable(db);
    await _createPdfChunksTable(db);
  }

  // ── Incremental migrations ───────────────────────────────────────────────

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createChatsTable(db);
    }
    if (oldVersion < 3) {
      // Add new profile columns (SQLite requires one ALTER TABLE per column)
      for (final sql in [
        "ALTER TABLE profiles ADD COLUMN lang_tamil       INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE profiles ADD COLUMN lang_english     INTEGER NOT NULL DEFAULT 1",
        "ALTER TABLE profiles ADD COLUMN age_group        TEXT    NOT NULL DEFAULT 'school'",
        "ALTER TABLE profiles ADD COLUMN age              INTEGER",
        "ALTER TABLE profiles ADD COLUMN school_name      TEXT",
        "ALTER TABLE profiles ADD COLUMN grade            TEXT",
        "ALTER TABLE profiles ADD COLUMN instr_examples   INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE profiles ADD COLUMN instr_disability INTEGER NOT NULL DEFAULT 0",
        "ALTER TABLE profiles ADD COLUMN custom_instructions TEXT",
      ]) {
        await db.execute(sql);
      }
      await _createFeedbackTable(db);
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE profiles ADD COLUMN reply_length TEXT');
    }
    if (oldVersion < 5) {
      await db.execute(
          'ALTER TABLE profiles ADD COLUMN ai_persona TEXT');
    }
    if (oldVersion < 6) {
      await _createRemindersTable(db);
      await _createBadgesTable(db);
    }
    if (oldVersion < 7) {
      await _createPdfChunksTable(db);
    }
  }

  // ── Table helpers ────────────────────────────────────────────────────────

  Future<void> _createChatsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chats (
        id          TEXT PRIMARY KEY,
        profile_id  TEXT NOT NULL,
        title       TEXT NOT NULL,
        created_at  INTEGER NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_chats_profile '
        'ON chats(profile_id, created_at)');
  }

  Future<void> _createFeedbackTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS feedback (
        id                TEXT PRIMARY KEY,
        profile_id        TEXT NOT NULL,
        chat_id           TEXT,
        message_id        TEXT NOT NULL,
        feedback_type     TEXT NOT NULL,
        original_prompt   TEXT NOT NULL,
        original_response TEXT NOT NULL,
        created_at        INTEGER NOT NULL,
        synced            INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_feedback_profile '
        'ON feedback(profile_id, created_at)');
  }

  Future<void> _createRemindersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS reminders (
        id               TEXT PRIMARY KEY,
        profile_id       TEXT NOT NULL,
        title            TEXT NOT NULL,
        type             TEXT NOT NULL DEFAULT 'custom',
        scheduled_hour   INTEGER NOT NULL,
        scheduled_minute INTEGER NOT NULL,
        once_at          INTEGER,
        is_daily         INTEGER NOT NULL DEFAULT 1,
        is_active        INTEGER NOT NULL DEFAULT 1,
        notification_id  INTEGER NOT NULL,
        created_at       INTEGER NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_reminders_profile '
        'ON reminders(profile_id, created_at)');
  }

  Future<void> _createBadgesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS badges (
        id           TEXT PRIMARY KEY,
        profile_id   TEXT NOT NULL,
        badge_type   TEXT NOT NULL,
        earned_at    INTEGER NOT NULL,
        FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_badges_unique '
        'ON badges(profile_id, badge_type)');
  }

  Future<void> _createPdfChunksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pdf_chunks (
        id          TEXT PRIMARY KEY,
        pdf_id      TEXT NOT NULL,
        profile_id  TEXT NOT NULL,
        page_number INTEGER NOT NULL,
        chunk_text  TEXT NOT NULL,
        embedding   BLOB,
        chunk_index INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (pdf_id) REFERENCES pdfs(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_chunks_pdf_page '
        'ON pdf_chunks(pdf_id, page_number)');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
