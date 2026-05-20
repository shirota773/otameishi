import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/search_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/screens/search_screen.dart';
import 'package:otameishi/theme/app_theme.dart';

class _FakeEventRepo extends Fake implements EventRepository {
  _FakeEventRepo(this.events);
  final List<Event> events;
  @override
  Future<List<Event>> findAll({bool orderByDateDesc = true}) async => events;
  @override
  Future<Event?> findById(String id) async =>
      events.where((e) => e.id == id).firstOrNull;
  @override
  Future<List<Event>> findByDateRange(DateTime from, DateTime to) async => [];
  @override
  Future<void> insert(Event event) async => events.add(event);
  @override
  Future<void> update(Event event) async {}
  @override
  Future<void> delete(String id) async {}
}

class _FakeTagRepo extends Fake implements TagRepository {
  _FakeTagRepo(this.tags);
  final List<Tag> tags;
  @override
  Future<List<Tag>> findAll() async => tags;
  @override
  Future<Tag> findOrCreate(String name) async =>
      Tag(id: 'new', name: name);
  @override
  Future<void> insert(Tag t) async {}
  @override
  Future<void> update(Tag t) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<List<TagWithCount>> findAllWithCounts() async => [];
}

class _FakeSearchRepo extends Fake implements SearchRepository {
  @override
  Future<List<BusinessCard>> search(
    String query, {
    Set<String>? eventIds,
    Set<String>? tagIds,
  }) async =>
      [];
}

class _FakeCardRepo extends Fake implements CardRepository {
  @override
  Future<BusinessCard?> findById(String id) async => null;
  @override
  Future<List<BusinessCard>> findAll({
    int? limit,
    int? offset,
    CardSortBy sortBy = CardSortBy.createdAt,
    bool includeMyCard = false,
  }) async =>
      [];
  @override
  Future<List<BusinessCard>> findByTag(String tagId) async => [];
  @override
  Future<List<BusinessCard>> findByEvent(String eventId) async => [];
  @override
  Future<void> insert(BusinessCard card) async {}
  @override
  Future<void> update(BusinessCard card) async {}
  @override
  Future<void> delete(String id) async {}
}

Widget _harness({
  required List<Event> events,
  required List<Tag> tags,
}) {
  return ProviderScope(
    overrides: [
      cardRepositoryProvider.overrideWith(
        (ref) async => _FakeCardRepo(),
      ),
      tagRepositoryProvider.overrideWith(
        (ref) async => _FakeTagRepo(tags),
      ),
      eventRepositoryProvider.overrideWith(
        (ref) async => _FakeEventRepo(events),
      ),
      searchRepositoryProvider.overrideWith(
        (ref) async => _FakeSearchRepo(),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const SearchScreen(),
    ),
  );
}

void main() {
  testWidgets('event filter sheet opens and shows items', (tester) async {
    final events = [
      Event(id: 'e1', name: 'コミケ106', date: DateTime(2026, 8, 12)),
      Event(id: 'e2', name: 'にじフェス'),
    ];
    await tester.pumpWidget(_harness(events: events, tags: const []));
    await tester.pumpAndSettle();

    expect(find.text('イベント'), findsOneWidget);
    await tester.tap(find.text('イベント'));
    await tester.pumpAndSettle();

    expect(find.text('イベントで絞り込み'), findsOneWidget);
    expect(find.text('コミケ106'), findsOneWidget);
    expect(find.text('にじフェス'), findsOneWidget);
  });

  testWidgets('tag filter sheet opens and shows items', (tester) async {
    final tags = [
      Tag(id: 't1', name: 'Vtuber'),
      Tag(id: 't2', name: 'コス'),
    ];
    await tester.pumpWidget(_harness(events: const [], tags: tags));
    await tester.pumpAndSettle();

    await tester.tap(find.text('タグ'));
    await tester.pumpAndSettle();

    expect(find.text('タグで絞り込み'), findsOneWidget);
    expect(find.text('Vtuber'), findsOneWidget);
    expect(find.text('コス'), findsOneWidget);
  });
}
