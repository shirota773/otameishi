import 'package:sqflite/sqflite.dart';

import 'migration.dart';

/// Migration 3: add back_image_path column to business_cards.
///
/// Named business cards are often double-sided; this optional column stores the
/// file-system path to the back-side image (nullable — existing rows get NULL).
///
/// No FTS impact: back_image_path is a file path, not searchable text.
/// No trigger changes required.
const Migration migration0003 = Migration(
  version: 3,
  up: _up,
);

Future<void> _up(Database db) async {
  await db.execute(
    'ALTER TABLE business_cards ADD COLUMN back_image_path TEXT',
  );
}
