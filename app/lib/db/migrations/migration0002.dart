import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Migration 2: many-to-many card↔event relationship.
///
/// Adds the [business_card_events] junction table so a single card can be
/// linked to multiple events.  The legacy [business_cards.event_id] column is
/// left in place (marked deprecated) to preserve backward-compatibility with
/// older app versions that may still be running against this database.
///
/// Data migration: every existing card whose [event_id] IS NOT NULL gets a
/// corresponding row inserted into [business_card_events].
///
/// FTS sync: the INSERT / UPDATE triggers on [business_cards] still read
/// [business_cards.event_id] for the [event_name] column.  New triggers added
/// here additionally fire on [business_card_events] mutations so that the FTS
/// row stays current when events are added or removed via the junction table.
const Migration migration0002 = Migration(
  version: 2,
  up: _up,
);

Future<void> _up(Database db) async {
  // ------------------------------------------------------------------ table
  await db.execute('''
    CREATE TABLE IF NOT EXISTS business_card_events (
      card_id  TEXT NOT NULL REFERENCES business_cards(id) ON DELETE CASCADE,
      event_id TEXT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
      PRIMARY KEY (card_id, event_id)
    )
  ''');

  // ----------------------------------------------------------------- index
  // Supports "find cards by event" queries through the junction table.
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_card_events_event '
    'ON business_card_events(event_id)',
  );

  // -------------------------------------------------------- data migration
  // For every card that already has a non-null event_id in the legacy column,
  // insert the equivalent junction row.  IGNORE on conflict is defensive only
  // (there should be none on a fresh migration).
  await db.execute('''
    INSERT OR IGNORE INTO business_card_events (card_id, event_id)
    SELECT id, event_id
    FROM business_cards
    WHERE event_id IS NOT NULL
  ''');

  // -------------------------------------------------- FTS sync triggers
  // When a row is inserted into business_card_events, refresh the FTS row
  // with all event names aggregated from the junction table.
  await db.execute('''
    CREATE TRIGGER IF NOT EXISTS trg_bce_fts_insert
    AFTER INSERT ON business_card_events
    BEGIN
      DELETE FROM cards_fts WHERE card_id = NEW.card_id;
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        bc.id,
        COALESCE(bc.display_name, ''),
        COALESCE(bc.memo, ''),
        COALESCE(
          (SELECT GROUP_CONCAT(e.name, ' ')
           FROM business_card_events bce2
           JOIN events e ON e.id = bce2.event_id
           WHERE bce2.card_id = bc.id),
          ''
        ),
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
    CREATE TRIGGER IF NOT EXISTS trg_bce_fts_delete
    AFTER DELETE ON business_card_events
    BEGIN
      DELETE FROM cards_fts WHERE card_id = OLD.card_id;
      INSERT INTO cards_fts(card_id, display_name, memo, event_name, tag_names)
      SELECT
        bc.id,
        COALESCE(bc.display_name, ''),
        COALESCE(bc.memo, ''),
        COALESCE(
          (SELECT GROUP_CONCAT(e.name, ' ')
           FROM business_card_events bce2
           JOIN events e ON e.id = bce2.event_id
           WHERE bce2.card_id = bc.id),
          ''
        ),
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
