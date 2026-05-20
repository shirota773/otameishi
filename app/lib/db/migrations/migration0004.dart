import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Migration 4: add is_my_card flag to business_cards.
///
/// Adds a boolean column (stored as INTEGER per SQLite convention) so exactly
/// one card can be designated as the user's own profile card ("マイカード").
/// Default is 0 (false) for all existing rows — no data migration required.
///
/// The index on is_my_card is cheap (one or zero rows will ever equal 1) and
/// makes the findMyCard lookup explicit and measurable via EXPLAIN QUERY PLAN.
const Migration migration0004 = Migration(
  version: 4,
  up: _up,
);

Future<void> _up(Database db) async {
  await db.execute(
    'ALTER TABLE business_cards ADD COLUMN is_my_card INTEGER NOT NULL DEFAULT 0',
  );

  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_business_cards_is_my_card '
    'ON business_cards(is_my_card)',
  );
}
