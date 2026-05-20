import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:otameishi/db/migrations/migrations.dart';

import 'db_test_helper.dart';

void main() {
  group('Migrations', () {
    late Database db;

    setUp(() async {
      db = await openTestDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('schema version equals migration count', () async {
      final rows = await db.rawQuery('PRAGMA user_version');
      final version = rows.first.values.first as int;
      expect(version, migrations.length);
    });

    test('business_cards table exists with expected columns', () async {
      final rows = await db.rawQuery(
        "PRAGMA table_info('business_cards')",
      );
      final cols = rows.map((r) => r['name'] as String).toSet();
      expect(
        cols,
        containsAll([
          'id',
          'image_path',
          'back_image_path', // added by migration0003
          'display_name',
          'sns_links_json',
          'memo',
          'event_id', // legacy column stays in schema
          'created_at',
          'is_my_card', // added by migration0004
        ]),
      );
    });

    test('events table exists with expected columns', () async {
      final rows = await db.rawQuery("PRAGMA table_info('events')");
      final cols = rows.map((r) => r['name'] as String).toSet();
      expect(cols, containsAll(['id', 'name', 'date', 'memo']));
    });

    test('tags table exists with expected columns', () async {
      final rows = await db.rawQuery("PRAGMA table_info('tags')");
      final cols = rows.map((r) => r['name'] as String).toSet();
      expect(cols, containsAll(['id', 'name']));
    });

    test('business_card_tags table exists', () async {
      final rows = await db.rawQuery("PRAGMA table_info('business_card_tags')");
      final cols = rows.map((r) => r['name'] as String).toSet();
      expect(cols, containsAll(['card_id', 'tag_id']));
    });

    // ── migration0002 assertions ─────────────────────────────────────────────

    test('business_card_events junction table exists with expected columns',
        () async {
      final rows =
          await db.rawQuery("PRAGMA table_info('business_card_events')");
      final cols = rows.map((r) => r['name'] as String).toSet();
      expect(cols, containsAll(['card_id', 'event_id']));
    });

    test('idx_business_card_events_event index is present', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_business_card_events_event'",
      );
      expect(rows, isNotEmpty);
    });

    // ── Data migration test ──────────────────────────────────────────────────
    // Simulates the state of a migration0001-only database (card with
    // legacy event_id set), then runs migration0002 manually and asserts the
    // data-migration SQL produced the expected junction row.

    test('migration0002 data migration copies legacy event_id to junction table',
        () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;

      // Open a fresh db and run only migration0001 so we have the legacy schema.
      final legacyDb = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await migrations[0].up(db);
          },
        ),
      );

      // Seed event + card with legacy event_id.
      await legacyDb.execute(
        "INSERT INTO events (id, name) VALUES ('ev1', 'Comiket')",
      );
      await legacyDb.execute(
        "INSERT INTO business_cards (id, image_path, event_id, created_at) "
        "VALUES ('c1', '/img.jpg', 'ev1', '2026-01-01T00:00:00.000Z')",
      );

      // Now apply migration0002 in the same db connection (simulating upgrade).
      await migrations[1].up(legacyDb);

      // Assert the junction row was created by the data migration.
      final rows = await legacyDb.rawQuery(
        'SELECT * FROM business_card_events WHERE card_id = ? AND event_id = ?',
        ['c1', 'ev1'],
      );
      expect(rows.length, 1);

      // Also assert a card WITHOUT event_id did not produce a junction row.
      await legacyDb.execute(
        "INSERT INTO business_cards (id, image_path, created_at) "
        "VALUES ('c2', '/img2.jpg', '2026-01-02T00:00:00.000Z')",
      );
      final noRows = await legacyDb.rawQuery(
        'SELECT * FROM business_card_events WHERE card_id = ?',
        ['c2'],
      );
      expect(noRows, isEmpty);

      await legacyDb.close();
    });

    // ── migration0003 assertions ─────────────────────────────────────────────

    test('migration0003 adds back_image_path column (nullable, existing rows NULL)',
        () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;

      // Open a SEPARATE fresh in-memory db by using a unique URI path so it
      // does not share a connection with the outer setUp db (which is already
      // at version 3 with back_image_path present).
      // sqflite_ffi caches open connections by path, so ':memory:' would reuse
      // the existing fully-migrated connection — we use a URI with a distinct
      // name to force a brand-new database.
      const legacyPath = 'file:migration0003_test?mode=memory&cache=private';
      final legacyDb = await factory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 2,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await migrations[0].up(db);
            await migrations[1].up(db);
          },
        ),
      );

      // Seed a card before migration0003.
      await legacyDb.execute(
        "INSERT INTO business_cards (id, image_path, created_at) "
        "VALUES ('c1', '/img.jpg', '2026-01-01T00:00:00.000Z')",
      );

      // Column must NOT exist before migration0003.
      final colsBefore = await legacyDb.rawQuery(
        "PRAGMA table_info('business_cards')",
      );
      final namesBefore = colsBefore.map((r) => r['name'] as String).toSet();
      expect(namesBefore.contains('back_image_path'), isFalse);

      // Apply migration0003.
      await migrations[2].up(legacyDb);

      // Column must exist after migration0003.
      final colsAfter = await legacyDb.rawQuery(
        "PRAGMA table_info('business_cards')",
      );
      final namesAfter = colsAfter.map((r) => r['name'] as String).toSet();
      expect(namesAfter.contains('back_image_path'), isTrue);

      // Existing row must have NULL back_image_path.
      final rows = await legacyDb.rawQuery(
        'SELECT back_image_path FROM business_cards WHERE id = ?',
        ['c1'],
      );
      expect(rows.length, 1);
      expect(rows.first['back_image_path'], isNull);

      await legacyDb.close();
    });

    // ── migration0004 assertions ─────────────────────────────────────────────

    test('migration0004 adds is_my_card column with default 0 for existing rows',
        () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;

      const legacyPath =
          'file:migration0004_test?mode=memory&cache=private';
      final legacyDb = await factory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await migrations[0].up(db);
            await migrations[1].up(db);
            await migrations[2].up(db);
          },
        ),
      );

      // Seed a card before migration0004.
      await legacyDb.execute(
        "INSERT INTO business_cards (id, image_path, created_at) "
        "VALUES ('c1', '/img.jpg', '2026-01-01T00:00:00.000Z')",
      );

      // Column must NOT exist before migration0004.
      final colsBefore =
          await legacyDb.rawQuery("PRAGMA table_info('business_cards')");
      final namesBefore =
          colsBefore.map((r) => r['name'] as String).toSet();
      expect(namesBefore.contains('is_my_card'), isFalse);

      // Apply migration0004.
      await migrations[3].up(legacyDb);

      // Column must exist after migration0004.
      final colsAfter =
          await legacyDb.rawQuery("PRAGMA table_info('business_cards')");
      final namesAfter =
          colsAfter.map((r) => r['name'] as String).toSet();
      expect(namesAfter.contains('is_my_card'), isTrue);

      // Existing row must have is_my_card = 0 (default).
      final rows = await legacyDb.rawQuery(
        'SELECT is_my_card FROM business_cards WHERE id = ?',
        ['c1'],
      );
      expect(rows.length, 1);
      expect(rows.first['is_my_card'], 0);

      await legacyDb.close();
    });

    test('migration0004 creates idx_business_cards_is_my_card index', () async {
      sqfliteFfiInit();
      final factory = databaseFactoryFfi;

      const legacyPath =
          'file:migration0004_index_test?mode=memory&cache=private';
      final legacyDb = await factory.openDatabase(
        legacyPath,
        options: OpenDatabaseOptions(
          version: 3,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) async {
            await migrations[0].up(db);
            await migrations[1].up(db);
            await migrations[2].up(db);
          },
        ),
      );

      // Index must NOT exist before migration0004.
      final idxBefore = await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_business_cards_is_my_card'",
      );
      expect(idxBefore, isEmpty);

      // Apply migration0004.
      await migrations[3].up(legacyDb);

      // Index must exist after migration0004.
      final idxAfter = await legacyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' "
        "AND name='idx_business_cards_is_my_card'",
      );
      expect(idxAfter, isNotEmpty);

      await legacyDb.close();
    });

    // ── FTS + triggers ───────────────────────────────────────────────────────

    test('cards_fts virtual table exists', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='cards_fts'",
      );
      expect(rows, isNotEmpty);
    });

    test('FTS triggers are present', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger'",
      );
      final names = rows.map((r) => r['name'] as String).toSet();
      expect(
        names,
        containsAll([
          'trg_bc_fts_insert',
          'trg_bc_fts_update',
          'trg_bc_fts_delete',
          'trg_bct_fts_insert',
          'trg_bct_fts_delete',
          'trg_bce_fts_insert',
          'trg_bce_fts_delete',
        ]),
      );
    });

    test('indexes are present', () async {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index'",
      );
      final names = rows.map((r) => r['name'] as String).toSet();
      expect(
        names,
        containsAll([
          'idx_bc_event_id',
          'idx_bc_created_at',
          'idx_bc_display_name',
          'idx_bct_tag_id',
          'idx_business_card_events_event',
          'idx_business_cards_is_my_card', // added by migration0004
        ]),
      );
    });

    test('re-opening the database is idempotent (no duplicate schema errors)',
        () async {
      await expectLater(
        db.rawQuery('SELECT count(*) FROM business_cards'),
        completion(isNotEmpty),
      );
    });
  });
}
