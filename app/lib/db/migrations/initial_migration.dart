import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Initial schema: tables, indexes, FTS5, and sync triggers.
///
/// FTS design note
/// ---------------
/// We use an FTS5 content table (content='business_cards') backed by an
/// external content model and maintain it with AFTER INSERT / AFTER UPDATE /
/// AFTER DELETE triggers on [business_cards].  The FTS row stores a denormalised
/// snapshot of searchable text: display_name, memo, the linked event name, and a
/// space-joined list of tag names.  The triggers rebuild the FTS row from a
/// SELECT that JOINs events and business_card_tags + tags at write time.
///
/// Tokenizer choice: `unicode61` handles full Unicode case-folding (good for
/// Latin scripts, romaji).  CJK characters are single-character tokens under
/// unicode61 — adequate for most Japanese name / event searches because the
/// query term is normally at least one character.  If bigram indexing is needed
/// later, add a new migration that rebuilds the FTS table with `trigram` or a
/// custom ICU tokenizer; this migration stays unchanged.
const Migration migration0001 = Migration(
  version: 1,
  up: _up,
);

Future<void> _up(Database db) async {
  // ------------------------------------------------------------------ tables
  await db.execute('''
    CREATE TABLE IF NOT EXISTS events (
      id        TEXT PRIMARY KEY,
      name      TEXT NOT NULL,
      date      TEXT,
      memo      TEXT
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_cards (
      id             TEXT PRIMARY KEY,
      image_path     TEXT NOT NULL,
      display_name   TEXT,
      sns_links_json TEXT,
      memo           TEXT,
      event_id       TEXT REFERENCES events(id) ON DELETE SET NULL,
      created_at     TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS tags (
      id   TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE COLLATE NOCASE
    )
  ''');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_card_tags (
      card_id TEXT NOT NULL REFERENCES business_cards(id) ON DELETE CASCADE,
      tag_id  TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      PRIMARY KEY (card_id, tag_id)
    )
  ''');

  // ----------------------------------------------------------------- indexes
  // FK columns that appear in JOINs and WHERE clauses.
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_bc_event_id ON business_cards(event_id)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_bc_created_at ON business_cards(created_at DESC)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_bc_display_name ON business_cards(display_name)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_bct_tag_id ON business_card_tags(tag_id)',
  );

  // -------------------------------------------------------------------- FTS5
  // Content table mirrors searchable text; rowid matches business_cards.rowid
  // via a mapping column (card_id stored UNINDEXED for retrieval).
  await db.execute('''
    CREATE VIRTUAL TABLE IF NOT EXISTS cards_fts USING fts5(
      card_id    UNINDEXED,
      display_name,
      memo,
      event_name,
      tag_names,
      tokenize   = 'unicode61'
    )
  ''');

  // ---------------------------------------------------------- sync triggers
  // Helper view is not available here, so triggers inline the JOIN query.
  // Each trigger rebuilds the FTS row for the affected card.

  // INSERT trigger: fires after a new card row is created.
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bc_fts_insert
    AFTER INSERT ON business_cards
    BEGIN
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        NEW.id,
        COALESCE(NEW.display_name, ''),
        COALESCE(NEW.memo, ''),
        COALESCE((SELECT name FROM events WHERE id = NEW.event_id), ''),
        COALESCE(
          (SELECT GROUP_CONCAT(t.name, ' ')
           FROM business_card_tags bct
           JOIN tags t ON t.id = bct.tag_id
           WHERE bct.card_id = NEW.id),
          ''
        );
    END
  ''');

  // UPDATE trigger: delete old FTS row, insert fresh snapshot.
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bc_fts_update
    AFTER UPDATE ON business_cards
    BEGIN
      DELETE FROM cards_fts WHERE card_id = OLD.id;
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        NEW.id,
        COALESCE(NEW.display_name, ''),
        COALESCE(NEW.memo, ''),
        COALESCE((SELECT name FROM events WHERE id = NEW.event_id), ''),
        COALESCE(
          (SELECT GROUP_CONCAT(t.name, ' ')
           FROM business_card_tags bct
           JOIN tags t ON t.id = bct.tag_id
           WHERE bct.card_id = NEW.id),
          ''
        );
    END
  ''');

  // DELETE trigger: remove FTS row when card is deleted.
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bc_fts_delete
    AFTER DELETE ON business_cards
    BEGIN
      DELETE FROM cards_fts WHERE card_id = OLD.id;
    END
  ''');

  // FTS sync on tag-association changes (INSERT / DELETE on business_card_tags).
  // When tags change, the card's tag_names column in FTS must be refreshed.
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bct_fts_insert
    AFTER INSERT ON business_card_tags
    BEGIN
      DELETE FROM cards_fts WHERE card_id = NEW.card_id;
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        bc.id,
        COALESCE(bc.display_name, ''),
        COALESCE(bc.memo, ''),
        COALESCE((SELECT name FROM events WHERE id = bc.event_id), ''),
        COALESCE(
          (SELECT GROUP_CONCAT(t.name, ' ')
           FROM business_card_tags bct
           JOIN tags t ON t.id = bct.tag_id
           WHERE bct.card_id = bc.id),
          ''
        )
      FROM business_cards bc
      WHERE bc.id = NEW.card_id;
    END
  ''');

  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bct_fts_delete
    AFTER DELETE ON business_card_tags
    BEGIN
      DELETE FROM cards_fts WHERE card_id = OLD.card_id;
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        bc.id,
        COALESCE(bc.display_name, ''),
        COALESCE(bc.memo, ''),
        COALESCE((SELECT name FROM events WHERE id = bc.event_id), ''),
        COALESCE(
          (SELECT GROUP_CONCAT(t.name, ' ')
           FROM business_card_tags bct
           JOIN tags t ON t.id = bct.tag_id
           WHERE bct.card_id = bc.id),
          ''
        )
      FROM business_cards bc
      WHERE bc.id = OLD.card_id;
    END
  ''');
}
