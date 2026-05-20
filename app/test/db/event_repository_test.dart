import 'package:flutter_test/flutter_test.dart';

import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/models/event.dart';

import 'db_test_helper.dart';

void main() {
  group('SqliteEventRepository', () {
    late Database db;
    late SqliteEventRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = SqliteEventRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    Event makeEvent({
      String id = 'e1',
      String name = 'コミケ106',
      DateTime? date,
      String? memo,
    }) {
      return Event(id: id, name: name, date: date, memo: memo);
    }

    test('findAll returns empty list when no events', () async {
      final events = await repo.findAll();
      expect(events, isEmpty);
    });

    test('insert then findById round-trips all fields', () async {
      final event = makeEvent(
        date: DateTime.utc(2026, 8, 11),
        memo: 'Summer Comiket',
      );
      await repo.insert(event);

      final found = await repo.findById('e1');
      expect(found, isNotNull);
      expect(found!.id, 'e1');
      expect(found.name, 'コミケ106');
      expect(found.date, DateTime.utc(2026, 8, 11));
      expect(found.memo, 'Summer Comiket');
    });

    test('findAll returns inserted events', () async {
      await repo.insert(makeEvent(id: 'e1', name: 'イベントA', date: DateTime.utc(2026, 1, 1)));
      await repo.insert(makeEvent(id: 'e2', name: 'イベントB', date: DateTime.utc(2026, 3, 1)));

      final events = await repo.findAll(orderByDateDesc: true);
      expect(events.length, 2);
      // Most recent date first.
      expect(events.first.id, 'e2');
      expect(events.last.id, 'e1');
    });

    test('findAll orderByDateDesc: false returns ascending', () async {
      await repo.insert(makeEvent(id: 'e1', name: 'A', date: DateTime.utc(2026, 1, 1)));
      await repo.insert(makeEvent(id: 'e2', name: 'B', date: DateTime.utc(2026, 3, 1)));

      final events = await repo.findAll(orderByDateDesc: false);
      expect(events.first.id, 'e1');
    });

    test('findById returns null for unknown id', () async {
      expect(await repo.findById('nope'), isNull);
    });

    test('update persists new values', () async {
      await repo.insert(makeEvent(name: 'Old Name'));
      final updated = makeEvent(name: 'New Name', memo: 'Updated');
      await repo.update(updated);

      final found = await repo.findById('e1');
      expect(found!.name, 'New Name');
      expect(found.memo, 'Updated');
    });

    test('delete removes the event', () async {
      await repo.insert(makeEvent());
      await repo.delete('e1');
      expect(await repo.findById('e1'), isNull);
    });

    test('findAll returns unmodifiable list', () async {
      await repo.insert(makeEvent());
      final events = await repo.findAll();
      final dummy = makeEvent(id: 'dummy');
      expect(() => (events as List<dynamic>).add(dummy), throwsUnsupportedError);
    });

    test('event with null date and memo round-trips', () async {
      await repo.insert(makeEvent(date: null, memo: null));
      final found = await repo.findById('e1');
      expect(found!.date, isNull);
      expect(found.memo, isNull);
    });

    // -------------------------------------------------------------------------
    // findByDateRange
    // -------------------------------------------------------------------------

    test('findByDateRange returns events within range inclusive', () async {
      await repo.insert(makeEvent(id: 'e1', name: 'Before', date: DateTime.utc(2026, 1, 1)));
      await repo.insert(makeEvent(id: 'e2', name: 'Start', date: DateTime.utc(2026, 3, 1)));
      await repo.insert(makeEvent(id: 'e3', name: 'Middle', date: DateTime.utc(2026, 5, 15)));
      await repo.insert(makeEvent(id: 'e4', name: 'End', date: DateTime.utc(2026, 8, 31)));
      await repo.insert(makeEvent(id: 'e5', name: 'After', date: DateTime.utc(2026, 9, 1)));

      final results = await repo.findByDateRange(
        DateTime.utc(2026, 3, 1),
        DateTime.utc(2026, 8, 31),
      );

      expect(results.map((e) => e.id).toList(), ['e2', 'e3', 'e4']);
    });

    test('findByDateRange returns empty list when no events overlap', () async {
      await repo.insert(makeEvent(id: 'e1', date: DateTime.utc(2025, 12, 31)));
      await repo.insert(makeEvent(id: 'e2', date: DateTime.utc(2027, 1, 1)));

      final results = await repo.findByDateRange(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(results, isEmpty);
    });

    test('findByDateRange excludes events with null date', () async {
      await repo.insert(makeEvent(id: 'e1', date: null));
      await repo.insert(makeEvent(id: 'e2', date: DateTime.utc(2026, 6, 1)));

      final results = await repo.findByDateRange(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(results.length, 1);
      expect(results.first.id, 'e2');
    });

    test('findByDateRange returns events in ascending date order', () async {
      await repo.insert(makeEvent(id: 'e1', name: 'C', date: DateTime.utc(2026, 12, 1)));
      await repo.insert(makeEvent(id: 'e2', name: 'A', date: DateTime.utc(2026, 2, 1)));
      await repo.insert(makeEvent(id: 'e3', name: 'B', date: DateTime.utc(2026, 7, 1)));

      final results = await repo.findByDateRange(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      expect(results.map((e) => e.id).toList(), ['e2', 'e3', 'e1']);
    });

    test('findByDateRange is inclusive at both boundaries', () async {
      final from = DateTime.utc(2026, 4, 1);
      final to = DateTime.utc(2026, 10, 1);

      await repo.insert(makeEvent(id: 'e1', date: from));
      await repo.insert(makeEvent(id: 'e2', date: to));

      final results = await repo.findByDateRange(from, to);
      expect(results.map((e) => e.id).toSet(), {'e1', 'e2'});
    });

    test('findByDateRange returns unmodifiable list', () async {
      await repo.insert(makeEvent(date: DateTime.utc(2026, 6, 1)));
      final results = await repo.findByDateRange(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 12, 31),
      );
      final dummy = makeEvent(id: 'dummy');
      expect(() => (results as List<dynamic>).add(dummy), throwsUnsupportedError);
    });
  });
}
