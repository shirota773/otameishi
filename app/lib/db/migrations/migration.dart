import 'package:sqflite/sqflite.dart';

/// A single, immutable database migration step.
///
/// Migrations are append-only: once shipped, a migration's [version] and [up]
/// function must never be changed. Add a new [Migration] for any schema change.
class Migration {
  const Migration({required this.version, required this.up});

  /// Schema version this migration brings the database TO.
  final int version;

  /// DDL / DML statements to apply when upgrading to [version].
  final Future<void> Function(Database db) up;
}
