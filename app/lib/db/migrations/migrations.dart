import 'migration.dart';
import 'initial_migration.dart';
import 'migration0002.dart';
import 'migration0003.dart';
import 'migration0004.dart';

export 'migration.dart';

/// Ordered list of all schema migrations.
///
/// Rules:
/// - Never remove or reorder entries.
/// - Never mutate an existing [Migration]; append a new one instead.
/// - Versions must be contiguous starting from 1.
const List<Migration> migrations = [
  migration0001,
  migration0002,
  migration0003,
  migration0004,
];
