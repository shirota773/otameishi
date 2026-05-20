import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:otameishi/db/database.dart';

// Re-export Database so callers can use it without importing sqflite directly.
export 'package:sqflite_common_ffi/sqflite_ffi.dart' show Database;

/// Opens a fresh in-memory SQLite database with all migrations applied.
/// Each call returns a new independent database suitable for isolated tests.
Future<Database> openTestDatabase() async {
  sqfliteFfiInit();
  final provider = DatabaseProvider(
    overridePath: inMemoryDatabasePath,
    overrideFactory: databaseFactoryFfi,
  );
  return provider.database;
}
