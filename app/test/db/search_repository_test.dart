import 'package:flutter_test/flutter_test.dart';

import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/search_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';

import 'db_test_helper.dart';

void main() {
  group('SqliteSearchRepository', () {
    late Database db;
    late SqliteCardRepository cardRepo;
    late SqliteTagRepository tagRepo;
    late SqliteEventRepository eventRepo;
    late SqliteSearchRepository searchRepo;

    setUp(() async {
      db = await openTestDatabase();
      cardRepo = SqliteCardRepository(db);
      tagRepo = SqliteTagRepository(db);
      eventRepo = SqliteEventRepository(db);
      searchRepo = SqliteSearchRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    BusinessCard makeCard({
      required String id,
      String? backImagePath,
      String? displayName,
      String? memo,
      List<Event> events = const [],
      List tags = const [],
      DateTime? createdAt,
    }) {
      return BusinessCard(
        id: id,
        imagePath: '/images/$id.jpg',
        backImagePath: backImagePath,
        displayName: displayName,
        snsLinks: const [],
        memo: memo,
        events: List.unmodifiable(events),
        createdAt: createdAt ?? DateTime.utc(2026, 5, 1),
        tags: List.unmodifiable(tags),
      );
    }

    test('empty query returns empty list', () async {
      final results = await searchRepo.search('');
      expect(results, isEmpty);
    });

    test('whitespace-only query returns empty list', () async {
      expect(await searchRepo.search('   '), isEmpty);
    });

    test('search hits display_name', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice'));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Bob'));

      final results = await searchRepo.search('Alice');
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('search hits memo', () async {
      await cardRepo.insert(makeCard(id: 'c1', memo: 'グッズ交換済'));
      await cardRepo.insert(makeCard(id: 'c2', memo: '別メモ'));

      final results = await searchRepo.search('グッズ交換済');
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('search hits event_name via junction table', () async {
      final event = Event(id: 'ev1', name: 'にじフェス2026');
      await eventRepo.insert(event);

      await cardRepo.insert(makeCard(id: 'c1', events: [event]));
      await cardRepo.insert(makeCard(id: 'c2'));

      final results = await searchRepo.search('にじフェス2026');
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('search hits tag_names', () async {
      final tag = await tagRepo.findOrCreate('Vtuber');
      await cardRepo.insert(makeCard(id: 'c1', tags: [tag]));
      await cardRepo.insert(makeCard(id: 'c2'));

      final results = await searchRepo.search('Vtuber');
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('search is case-insensitive for ASCII', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice'));
      final results = await searchRepo.search('alice');
      expect(results.length, 1);
    });

    test('search returns empty for no matches', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice'));
      expect(await searchRepo.search('xyz_no_match'), isEmpty);
    });

    test('search returns unmodifiable list', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice'));
      final results = await searchRepo.search('Alice');
      final dummy = makeCard(id: 'dummy');
      expect(
        () => (results as List<dynamic>).add(dummy),
        throwsUnsupportedError,
      );
    });

    test('search for Japanese name returns correct card', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: '田中さくら'));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Bob'));

      final results = await searchRepo.search('田中さくら');
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('FTS updates when card is updated', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'OldName'));

      final updated = BusinessCard(
        id: 'c1',
        imagePath: '/images/c1.jpg',
        displayName: 'NewName',
        snsLinks: const [],
        memo: null,
        events: const [],
        createdAt: DateTime.utc(2026, 5, 1),
        tags: const [],
      );
      await cardRepo.update(updated);

      expect(await searchRepo.search('OldName'), isEmpty);
      expect(await searchRepo.search('NewName'), isNotEmpty);
    });

    test('FTS row deleted when card is deleted', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'DeleteMe'));
      await cardRepo.delete('c1');
      expect(await searchRepo.search('DeleteMe'), isEmpty);
    });

    test('multiple matches return multiple results', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'testuser'));
      await cardRepo.insert(makeCard(id: 'c2', memo: 'testmemo'));
      await cardRepo.insert(makeCard(id: 'c3', displayName: 'other'));

      final results = await searchRepo.search('test');
      expect(results.length, 2);
      final ids = results.map((c) => c.id).toSet();
      expect(ids, containsAll(['c1', 'c2']));
    });

    test('user input with FTS special chars does not throw', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'safe'));
      await expectLater(searchRepo.search('AND OR NOT'), completes);
      await expectLater(searchRepo.search('"quoted"'), completes);
    });

    // ── Advanced filter tests ────────────────────────────────────────────────

    test('filter-only by eventId via junction table returns matching cards',
        () async {
      final event = Event(id: 'ev1', name: 'コミケ106');
      await eventRepo.insert(event);

      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice', events: [event]));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Bob'));

      final results = await searchRepo.search('', eventIds: {'ev1'});
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('combined query + eventId filter narrows results correctly', () async {
      final event1 = Event(id: 'ev1', name: 'にじフェス2026');
      final event2 = Event(id: 'ev2', name: 'コミケ107');
      await eventRepo.insert(event1);
      await eventRepo.insert(event2);

      await cardRepo.insert(
          makeCard(id: 'c1', displayName: 'Alice', events: [event1]));
      await cardRepo.insert(
          makeCard(id: 'c2', displayName: 'Alice', events: [event2]));
      await cardRepo.insert(
          makeCard(id: 'c3', displayName: 'Bob', events: [event1]));

      final results =
          await searchRepo.search('Alice', eventIds: {'ev1'});
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('filter-only by tagId returns matching cards without a query',
        () async {
      final tag = await tagRepo.findOrCreate('oshi');
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Fan', tags: [tag]));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Other'));

      final results = await searchRepo.search('', tagIds: {tag.id});
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('empty query with empty filters returns empty list', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Alice'));
      final results = await searchRepo.search('');
      expect(results, isEmpty);
    });

    test('card linked to multiple events appears once per event filter', () async {
      final ev1 = Event(id: 'ev1', name: 'Fest');
      final ev2 = Event(id: 'ev2', name: 'Live');
      await eventRepo.insert(ev1);
      await eventRepo.insert(ev2);

      await cardRepo.insert(makeCard(id: 'c1', events: [ev1, ev2]));

      // Filtering by ev1 should return c1 exactly once.
      final results = await searchRepo.search('', eventIds: {'ev1'});
      expect(results.length, 1);
      expect(results.first.id, 'c1');
    });

    test('backImagePath is present in search result rows', () async {
      await cardRepo.insert(makeCard(
        id: 'c1',
        displayName: 'BackTest',
        backImagePath: '/images/c1_back.jpg',
      ));

      final results = await searchRepo.search('BackTest');
      expect(results.length, 1);
      expect(results.first.backImagePath, '/images/c1_back.jpg');
    });

    test('backImagePath is null in search result when not set', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'NoBack'));

      final results = await searchRepo.search('NoBack');
      expect(results.length, 1);
      expect(results.first.backImagePath, isNull);
    });

    test('returned cards from search have events eagerly loaded', () async {
      final ev = Event(id: 'ev1', name: 'にじフェス');
      await eventRepo.insert(ev);
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Fan', events: [ev]));

      final results = await searchRepo.search('Fan');
      expect(results.first.events.length, 1);
      expect(results.first.events.first.id, 'ev1');
    });

    // ── my-card exclusion ────────────────────────────────────────────────────

    test('search excludes my-card from text query results', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'マイカード'));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'マイカード'));
      await cardRepo.setMyCard('c1');

      final results = await searchRepo.search('マイカード');
      final ids = results.map((c) => c.id).toList();
      expect(ids, isNot(contains('c1')));
      expect(ids, contains('c2'));
    });

    test('search excludes my-card from event-filter-only results', () async {
      final event = Event(id: 'ev1', name: 'Fest');
      await eventRepo.insert(event);
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Own', events: [event]));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Other', events: [event]));
      await cardRepo.setMyCard('c1');

      final results = await searchRepo.search('', eventIds: {'ev1'});
      final ids = results.map((c) => c.id).toList();
      expect(ids, isNot(contains('c1')));
      expect(ids, contains('c2'));
    });

    test('search excludes my-card from tag-filter-only results', () async {
      final tag = await tagRepo.findOrCreate('oshi');
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Own', tags: [tag]));
      await cardRepo.insert(makeCard(id: 'c2', displayName: 'Other', tags: [tag]));
      await cardRepo.setMyCard('c1');

      final results = await searchRepo.search('', tagIds: {tag.id});
      final ids = results.map((c) => c.id).toList();
      expect(ids, isNot(contains('c1')));
      expect(ids, contains('c2'));
    });

    test('isMyCard field is false on cards returned from search', () async {
      await cardRepo.insert(makeCard(id: 'c1', displayName: 'Normal'));

      final results = await searchRepo.search('Normal');
      expect(results.first.isMyCard, isFalse);
    });
  });
}
