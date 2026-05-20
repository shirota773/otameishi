import 'dart:async';
import 'dart:io' show Platform;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations/migrations.dart';

bool _ffiInitialised = false;

/// Initialise the FFI sqflite backend on mobile so we ship a SQLite build
/// that includes FTS5.  Android's system SQLite omits FTS5; iOS includes it
/// but using FFI uniformly keeps the schema identical on every platform.
void _ensureFfiInitialised() {
  if (_ffiInitialised) return;
  if (Platform.isAndroid || Platform.isIOS) {
    // sqlite3_flutter_libs provides the native sqlite3 library on Android/iOS.
    // sqfliteFfiInit() wires that up to the sqflite_common_ffi factory.
    sqfliteFfiInit();
  } else {
    // Desktop/test contexts.
    sqfliteFfiInit();
  }
  _ffiInitialised = true;
}

/// Opens and manages the single SQLite database instance.
///
/// Location policy (backup-friendly):
/// - iOS: [getApplicationDocumentsDirectory] → included in iCloud Backup by
///   default.  The Documents directory is the correct OS-backup-eligible path
///   on iOS (NSDocumentDirectory).
/// - Android: [getApplicationDocumentsDirectory] resolves to the app's internal
///   files/Documents directory, which is covered by Android Auto Backup
///   (minSdkVersion ≥ 23) because it falls under the app's internal storage
///   (`files/`).  No `android:allowBackup="false"` must be set in the manifest.
///
/// For unit / integration tests supply [overridePath] to use an in-memory or
/// temporary file database without touching the device filesystem.
class DatabaseProvider {
  DatabaseProvider({this.overridePath, this.overrideFactory});

  /// Optional absolute path override used in tests.
  final String? overridePath;

  /// Optional sqflite factory override (e.g. [databaseFactoryFfi] in tests).
  final DatabaseFactory? overrideFactory;

  Database? _db;

  static const String _dbName = 'otameishi.db';

  /// Returns the open [Database], opening it on first call.
  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// Closes the database. Subsequent calls to [database] will reopen it.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<Database> _open() async {
    final DatabaseFactory factory;
    if (overrideFactory != null) {
      factory = overrideFactory!;
    } else {
      _ensureFfiInitialised();
      factory = databaseFactoryFfi;
    }

    final String path;
    if (overridePath != null) {
      path = overridePath!;
    } else {
      final dir = await getApplicationDocumentsDirectory();
      path = p.join(dir.path, _dbName);
    }

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: migrations.length,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// Enable foreign-key enforcement (off by default in SQLite).
  static Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Fresh install: run all migrations in order.
  static Future<void> _onCreate(Database db, int version) async {
    for (final m in migrations) {
      await m.up(db);
    }
  }

  /// Upgrade: run only the migrations needed to reach [newVersion].
  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (final m in migrations) {
      if (m.version > oldVersion && m.version <= newVersion) {
        await m.up(db);
      }
    }
  }
}
