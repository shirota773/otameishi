import 'package:flutter_test/flutter_test.dart';

import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';

import 'db_test_helper.dart';

void main() {
  group('SqliteCardRepository', () {
    late Database db;
    late SqliteCardRepository cardRepo;
    late SqliteTagRepository tagRepo;
    late SqliteEventRepository eventRepo;

    setUp(() async {
      db = await openTestDatabase();
      cardRepo = SqliteCardRepository(db);
      tagRepo = SqliteTagRepository(db);
      eventRepo = SqliteEventRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    BusinessCard makeCard({
      String id = 'c1',
      String imagePath = '/images/c1.jpg',
      String? backImagePath,
      String? displayName = 'テストユーザー',
      List<String> snsLinks = const [],
      String? memo,
      List<Event> events = const [],
      DateTime? createdAt,
      List<Tag> tags = const [],
    }) {
      return BusinessCard(
        id: id,
        imagePath: imagePath,
        backImagePath: backImagePath,
        displayName: displayName,
        snsLinks: List.unmodifiable(snsLinks),
        memo: memo,
        events: List.unmodifiable(events),
        createdAt: createdAt ?? DateTime.utc(2026, 5, 1),
        tags: List.unmodifiable(tags),
      );
    }

    test('findById returns null for unknown id', () async {
      expect(await cardRepo.findById('nope'), isNull);
    });

    test('insert then findById round-trips all scalar fields', () async {
      final card = makeCard(
        snsLinks: ['https://x.com/test'],
        memo: 'メモ',
        createdAt: DateTime.utc(2026, 5, 1, 12),
      );
      await cardRepo.insert(card);

      final found = await cardRepo.findById('c1');
      expect(found, isNotNull);
      expect(found!.id, 'c1');
      expect(found.imagePath, '/images/c1.jpg');
      expect(found.displayName, 'テストユーザー');
      expect(found.snsLinks, ['https://x.com/test']);
      expect(found.memo, 'メモ');
      expect(found.createdAt, DateTime.utc(2026, 5, 1, 12));
    });

    test('backImagePath round-trips: set value', () async {
      final card = makeCard(backImagePath: '/images/c1_back.jpg');
      await cardRepo.insert(card);

      final found = await cardRepo.findById('c1');
      expect(found!.backImagePath, '/images/c1_back.jpg');
    });

    test('backImagePath round-trips: null value', () async {
      final card = makeCard();
      await cardRepo.insert(card);

      final found = await cardRepo.findById('c1');
      expect(found!.backImagePath, isNull);
    });

    test('backImagePath is updated on card update', () async {
      await cardRepo.insert(makeCard());

      final updated = makeCard(backImagePath: '/images/c1_back.jpg');
      await cardRepo.update(updated);

      final found = await cardRepo.findById('c1');
      expect(found!.backImagePath, '/images/c1_back.jpg');
    });

    test('insert with tags — tags are eagerly loaded', () async {
      final tag1 = await tagRepo.findOrCreate('Vtuber');
      final tag2 = await tagRepo.findOrCreate('コス');

      final card = makeCard(tags: [tag1, tag2]);
      await cardRepo.insert(card);

      final found = await cardRepo.findById('c1');
      expect(found!.tags.length, 2);
      final tagNames = found.tags.map((t) => t.name).toSet();
      expect(tagNames, containsAll(['Vtuber', 'コス']));
    });

    // ── Many-to-many event association ───────────────────────────────────────

    test('card with 0 events has empty events list', () async {
      await cardRepo.insert(makeCard());
      final found = await cardRepo.findById('c1');
      expect(found!.events, isEmpty);
    });

    test('card with 1 event — event is eagerly loaded', () async {
      final ev = Event(id: 'ev1', name: 'コミケ106');
      await eventRepo.insert(ev);

      await cardRepo.insert(makeCard(events: [ev]));

      final found = await cardRepo.findById('c1');
      expect(found!.events.length, 1);
      expect(found.events.first.id, 'ev1');
      expect(found.events.first.name, 'コミケ106');
    });

    test('card with 2 events — both events are eagerly loaded', () async {
      final ev1 = Event(id: 'ev1', name: 'にじフェス2026');
      final ev2 = Event(id: 'ev2', name: 'コミケ107');
      await eventRepo.insert(ev1);
      await eventRepo.insert(ev2);

      await cardRepo.insert(makeCard(events: [ev1, ev2]));

      final found = await cardRepo.findById('c1');
      expect(found!.events.length, 2);
      final eventIds = found.events.map((e) => e.id).toSet();
      expect(eventIds, containsAll(['ev1', 'ev2']));
    });

    test('deleting an event cascades to junction table', () async {
      final ev = Event(id: 'ev1', name: 'TestEvent');
      await eventRepo.insert(ev);
      await cardRepo.insert(makeCard(events: [ev]));

      await eventRepo.delete('ev1');

      // Junction row gone.
      final rows = await db.rawQuery(
        'SELECT * FROM business_card_events WHERE card_id = ? AND event_id = ?',
        ['c1', 'ev1'],
      );
      expect(rows, isEmpty);

      // Card's events list is now empty.
      final found = await cardRepo.findById('c1');
      expect(found!.events, isEmpty);
    });

    test('deleting a card cascades to business_card_events', () async {
      final ev = Event(id: 'ev1', name: 'TestEvent');
      await eventRepo.insert(ev);
      await cardRepo.insert(makeCard(events: [ev]));
      await cardRepo.delete('c1');

      final rows = await db.rawQuery(
        'SELECT * FROM business_card_events WHERE card_id = ?',
        ['c1'],
      );
      expect(rows, isEmpty);
    });

    test('findAll returns empty list when no cards', () async {
      expect(await cardRepo.findAll(), isEmpty);
    });

    test('findAll paginates correctly', () async {
      for (var i = 1; i <= 5; i++) {
        await cardRepo.insert(makeCard(
          id: 'c$i',
          imagePath: '/images/c$i.jpg',
          createdAt: DateTime.utc(2026, 5, i),
        ));
      }

      final page1 = await cardRepo.findAll(limit: 2, offset: 0);
      final page2 = await cardRepo.findAll(limit: 2, offset: 2);
      final page3 = await cardRepo.findAll(limit: 2, offset: 4);

      expect(page1.length, 2);
      expect(page2.length, 2);
      expect(page3.length, 1);
    });

    test('findAll sorts by createdAt DESC by default', () async {
      await cardRepo.insert(
          makeCard(id: 'c1', createdAt: DateTime.utc(2026, 1, 1)));
      await cardRepo.insert(
          makeCard(id: 'c2', imagePath: '/images/c2.jpg', createdAt: DateTime.utc(2026, 3, 1)));
      final cards = await cardRepo.findAll(sortBy: CardSortBy.createdAt);
      expect(cards.first.id, 'c2');
    });

    test('findAll sorts by name ASC', () async {
      await cardRepo.insert(
          makeCard(id: 'c1', displayName: 'Z', createdAt: DateTime.utc(2026, 1)));
      await cardRepo.insert(makeCard(
          id: 'c2',
          imagePath: '/images/c2.jpg',
          displayName: 'A',
          createdAt: DateTime.utc(2026, 2)));
      final cards = await cardRepo.findAll(sortBy: CardSortBy.name);
      expect(cards.first.displayName, 'A');
    });

    test('findAll sorts by event then createdAt', () async {
      final e1 = Event(id: 'ev1', name: 'AAA');
      final e2 = Event(id: 'ev2', name: 'BBB');
      await eventRepo.insert(e1);
      await eventRepo.insert(e2);

      await cardRepo.insert(makeCard(
          id: 'c1',
          imagePath: '/images/c1.jpg',
          events: [e2],
          createdAt: DateTime.utc(2026, 1)));
      await cardRepo.insert(makeCard(
          id: 'c2',
          imagePath: '/images/c2.jpg',
          events: [e1],
          createdAt: DateTime.utc(2026, 2)));

      final cards = await cardRepo.findAll(sortBy: CardSortBy.event);
      // ev1 < ev2 alphabetically so c2 (ev1) should come first.
      expect(cards.first.id, 'c2');
      expect(cards.last.id, 'c1');
    });

    test('findByTag returns only cards with that tag', () async {
      final tagA = await tagRepo.findOrCreate('A');
      final tagB = await tagRepo.findOrCreate('B');

      await cardRepo.insert(makeCard(id: 'c1', tags: [tagA]));
      await cardRepo.insert(makeCard(
          id: 'c2', imagePath: '/images/c2.jpg', tags: [tagA, tagB]));
      await cardRepo.insert(
          makeCard(id: 'c3', imagePath: '/images/c3.jpg', tags: [tagB]));

      final byA = await cardRepo.findByTag(tagA.id);
      expect(byA.length, 2);
      expect(byA.map((c) => c.id).toSet(), {'c1', 'c2'});

      final byB = await cardRepo.findByTag(tagB.id);
      expect(byB.length, 2);
      expect(byB.map((c) => c.id).toSet(), {'c2', 'c3'});
    });

    test('findByEvent returns only cards linked to that event', () async {
      final event = Event(id: 'ev1', name: 'TestEvent');
      await eventRepo.insert(event);

      await cardRepo.insert(makeCard(id: 'c1', events: [event]));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));

      final cards = await cardRepo.findByEvent('ev1');
      expect(cards.length, 1);
      expect(cards.first.id, 'c1');
    });

    test('findByEvent returns card linked to multiple events', () async {
      final ev1 = Event(id: 'ev1', name: 'Fest');
      final ev2 = Event(id: 'ev2', name: 'Comiket');
      await eventRepo.insert(ev1);
      await eventRepo.insert(ev2);

      // c1 is linked to both events; c2 only to ev2.
      await cardRepo.insert(makeCard(id: 'c1', events: [ev1, ev2]));
      await cardRepo.insert(makeCard(
          id: 'c2', imagePath: '/images/c2.jpg', events: [ev2]));

      final byEv1 = await cardRepo.findByEvent('ev1');
      expect(byEv1.length, 1);
      expect(byEv1.first.id, 'c1');

      final byEv2 = await cardRepo.findByEvent('ev2');
      expect(byEv2.length, 2);
      expect(byEv2.map((c) => c.id).toSet(), {'c1', 'c2'});
    });

    test('update persists changes including tag replacement', () async {
      final tagOld = await tagRepo.findOrCreate('Old');
      final tagNew = await tagRepo.findOrCreate('New');

      await cardRepo.insert(makeCard(tags: [tagOld]));

      final updated = makeCard(
        memo: 'Updated memo',
        tags: [tagNew],
      );
      await cardRepo.update(updated);

      final found = await cardRepo.findById('c1');
      expect(found!.memo, 'Updated memo');
      expect(found.tags.length, 1);
      expect(found.tags.first.name, 'New');
    });

    test('update replaces event links atomically', () async {
      final ev1 = Event(id: 'ev1', name: 'Before');
      final ev2 = Event(id: 'ev2', name: 'After');
      await eventRepo.insert(ev1);
      await eventRepo.insert(ev2);

      await cardRepo.insert(makeCard(events: [ev1]));

      final updated = makeCard(events: [ev2]);
      await cardRepo.update(updated);

      final found = await cardRepo.findById('c1');
      expect(found!.events.length, 1);
      expect(found.events.first.id, 'ev2');
    });

    test('delete removes the card', () async {
      await cardRepo.insert(makeCard());
      await cardRepo.delete('c1');
      expect(await cardRepo.findById('c1'), isNull);
    });

    test('delete cascades to business_card_tags', () async {
      final tag = await tagRepo.findOrCreate('X');
      await cardRepo.insert(makeCard(tags: [tag]));
      await cardRepo.delete('c1');

      final rows = await db.rawQuery(
        'SELECT * FROM business_card_tags WHERE card_id = ?',
        ['c1'],
      );
      expect(rows, isEmpty);
    });

    test('findAll returns unmodifiable list', () async {
      await cardRepo.insert(makeCard());
      final cards = await cardRepo.findAll();
      final dummy = makeCard(id: 'dummy', imagePath: '/dummy.jpg');
      expect(() => (cards as List<dynamic>).add(dummy), throwsUnsupportedError);
    });

    test('returned card.tags is unmodifiable', () async {
      final tag = await tagRepo.findOrCreate('T');
      await cardRepo.insert(makeCard(tags: [tag]));
      final card = await cardRepo.findById('c1');
      expect(
        () => (card!.tags as List<dynamic>).add(tag),
        throwsUnsupportedError,
      );
    });

    test('returned card.events is unmodifiable', () async {
      final ev = Event(id: 'ev1', name: 'E');
      await eventRepo.insert(ev);
      await cardRepo.insert(makeCard(events: [ev]));
      final card = await cardRepo.findById('c1');
      expect(
        () => (card!.events as List<dynamic>).add(ev),
        throwsUnsupportedError,
      );
    });

    test('card with null displayName and empty events round-trips', () async {
      await cardRepo.insert(makeCard(displayName: null, events: const []));
      final found = await cardRepo.findById('c1');
      expect(found!.displayName, isNull);
      expect(found.events, isEmpty);
    });

    // ── isMyCard field ───────────────────────────────────────────────────────

    test('isMyCard defaults to false on insert and round-trips via findById',
        () async {
      await cardRepo.insert(makeCard());
      final found = await cardRepo.findById('c1');
      expect(found!.isMyCard, isFalse);
    });

    test('insert with isMyCard=true round-trips via findById', () async {
      final card = BusinessCard(
        id: 'c1',
        imagePath: '/images/c1.jpg',
        snsLinks: const [],
        events: const [],
        createdAt: DateTime.utc(2026, 5, 1),
        tags: const [],
        isMyCard: true,
      );
      await cardRepo.insert(card);
      final found = await cardRepo.findById('c1');
      expect(found!.isMyCard, isTrue);
    });

    // ── findMyCard ───────────────────────────────────────────────────────────

    test('findMyCard returns null when no card is flagged', () async {
      await cardRepo.insert(makeCard());
      expect(await cardRepo.findMyCard(), isNull);
    });

    test('findMyCard returns the card with is_my_card=1', () async {
      await cardRepo.insert(makeCard(id: 'c1'));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));

      await cardRepo.setMyCard('c1');

      final myCard = await cardRepo.findMyCard();
      expect(myCard, isNotNull);
      expect(myCard!.id, 'c1');
      expect(myCard.isMyCard, isTrue);
    });

    // ── setMyCard ────────────────────────────────────────────────────────────

    test('setMyCard sets flag on the target card', () async {
      await cardRepo.insert(makeCard());
      await cardRepo.setMyCard('c1');

      final found = await cardRepo.findById('c1');
      expect(found!.isMyCard, isTrue);
    });

    test('setMyCard switches flag from one card to another atomically',
        () async {
      await cardRepo.insert(makeCard(id: 'c1'));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));

      await cardRepo.setMyCard('c1');
      // c1 is now my-card; switch to c2.
      await cardRepo.setMyCard('c2');

      final c1 = await cardRepo.findById('c1');
      final c2 = await cardRepo.findById('c2');
      expect(c1!.isMyCard, isFalse);
      expect(c2!.isMyCard, isTrue);

      // Exactly one my-card in total.
      final myCard = await cardRepo.findMyCard();
      expect(myCard!.id, 'c2');
    });

    test('setMyCard does not affect other cards beyond clearing the old flag',
        () async {
      await cardRepo.insert(makeCard(id: 'c1'));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));
      await cardRepo.insert(makeCard(id: 'c3', imagePath: '/images/c3.jpg'));

      await cardRepo.setMyCard('c2');
      await cardRepo.setMyCard('c3');

      final all = await cardRepo.findAll(includeMyCard: true);
      final myCards = all.where((c) => c.isMyCard).toList();
      expect(myCards.length, 1);
      expect(myCards.first.id, 'c3');
    });

    // ── clearMyCard ──────────────────────────────────────────────────────────

    test('clearMyCard removes the flag from the current my-card', () async {
      await cardRepo.insert(makeCard());
      await cardRepo.setMyCard('c1');
      await cardRepo.clearMyCard();

      expect(await cardRepo.findMyCard(), isNull);
      final found = await cardRepo.findById('c1');
      expect(found!.isMyCard, isFalse);
    });

    test('clearMyCard is a no-op when no my-card is set', () async {
      await cardRepo.insert(makeCard());
      // Should not throw.
      await expectLater(cardRepo.clearMyCard(), completes);
      expect(await cardRepo.findMyCard(), isNull);
    });

    // ── findAll my-card exclusion ────────────────────────────────────────────

    test('findAll excludes my-card by default', () async {
      await cardRepo.insert(makeCard(id: 'c1'));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));
      await cardRepo.setMyCard('c1');

      final all = await cardRepo.findAll();
      expect(all.map((c) => c.id).toList(), isNot(contains('c1')));
      expect(all.map((c) => c.id).toList(), contains('c2'));
    });

    test('findAll includes my-card when includeMyCard is true', () async {
      await cardRepo.insert(makeCard(id: 'c1'));
      await cardRepo.insert(makeCard(id: 'c2', imagePath: '/images/c2.jpg'));
      await cardRepo.setMyCard('c1');

      final all = await cardRepo.findAll(includeMyCard: true);
      final ids = all.map((c) => c.id).toSet();
      expect(ids, containsAll(['c1', 'c2']));
    });

    // ── findByTag my-card exclusion ──────────────────────────────────────────

    test('findByTag excludes my-card', () async {
      final tag = await tagRepo.findOrCreate('VIP');
      await cardRepo.insert(makeCard(id: 'c1', tags: [tag]));
      await cardRepo.insert(
          makeCard(id: 'c2', imagePath: '/images/c2.jpg', tags: [tag]));
      await cardRepo.setMyCard('c1');

      final byTag = await cardRepo.findByTag(tag.id);
      expect(byTag.map((c) => c.id).toList(), isNot(contains('c1')));
      expect(byTag.map((c) => c.id).toList(), contains('c2'));
    });

    // ── findByEvent my-card exclusion ────────────────────────────────────────

    test('findByEvent excludes my-card', () async {
      final ev = Event(id: 'ev1', name: 'コミケ');
      await eventRepo.insert(ev);
      await cardRepo.insert(makeCard(id: 'c1', events: [ev]));
      await cardRepo.insert(
          makeCard(id: 'c2', imagePath: '/images/c2.jpg', events: [ev]));
      await cardRepo.setMyCard('c1');

      final byEvent = await cardRepo.findByEvent('ev1');
      expect(byEvent.map((c) => c.id).toList(), isNot(contains('c1')));
      expect(byEvent.map((c) => c.id).toList(), contains('c2'));
    });
  });
}
