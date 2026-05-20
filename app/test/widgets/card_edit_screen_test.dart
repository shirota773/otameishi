import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/screens/card_edit_screen.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/services/storage_service.dart';
import 'package:otameishi/theme/app_theme.dart';
import 'package:otameishi/usecases/update_card_usecase.dart';

class _NoopStorage implements StorageService {
  @override
  Future<String> saveCardImage(
    Uint8List bytes, {
    required ImageFormat format,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteCardImage(String path) async {}

  @override
  Future<int> cleanupOrphans(Set<String> validPaths) async => 0;
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeTagRepository extends Fake implements TagRepository {
  final List<Tag> tags;
  _FakeTagRepository(this.tags);

  @override
  Future<List<Tag>> findAll() async => List.unmodifiable(tags);

  @override
  Future<Tag> findOrCreate(String name) async {
    final existing = tags.where((t) => t.name == name).firstOrNull;
    if (existing != null) return existing;
    final t = Tag(id: 'new-$name', name: name);
    tags.add(t);
    return t;
  }

  @override
  Future<void> insert(Tag tag) async => tags.add(tag);

  @override
  Future<void> update(Tag tag) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<TagWithCount>> findAllWithCounts() async =>
      List.unmodifiable(tags.map((t) => TagWithCount(tag: t, cardCount: 0)));
}

class _FakeEventRepository extends Fake implements EventRepository {
  final List<Event> events;
  _FakeEventRepository(this.events);

  @override
  Future<List<Event>> findAll({bool orderByDateDesc = true}) async =>
      List.unmodifiable(events);

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

class _FakeCardRepository extends Fake implements CardRepository {
  final List<BusinessCard> cards;
  _FakeCardRepository(this.cards);

  @override
  Future<BusinessCard?> findById(String id) async =>
      cards.where((c) => c.id == id).firstOrNull;

  @override
  Future<List<BusinessCard>> findAll({
    int? limit,
    int? offset,
    CardSortBy sortBy = CardSortBy.createdAt,
    bool includeMyCard = false,
  }) async =>
      List.unmodifiable(cards);

  @override
  Future<List<BusinessCard>> findByTag(String tagId) async => [];

  @override
  Future<List<BusinessCard>> findByEvent(String eventId) async => [];

  @override
  Future<void> insert(BusinessCard card) async => cards.add(card);

  @override
  Future<void> update(BusinessCard card) async {
    final idx = cards.indexWhere((c) => c.id == card.id);
    if (idx >= 0) cards[idx] = card;
  }

  @override
  Future<void> delete(String id) async =>
      cards.removeWhere((c) => c.id == id);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BusinessCard _makeCard({
  String id = 'card-1',
  String displayName = '山田太郎',
  String memo = 'テストメモ',
  List<Tag> tags = const [],
  List<Event> events = const [],
  List<String> snsLinks = const [],
}) =>
    BusinessCard(
      id: id,
      imagePath: '/nonexistent/card.jpg',
      displayName: displayName,
      snsLinks: List.unmodifiable(snsLinks),
      memo: memo,
      events: List.unmodifiable(events),
      createdAt: DateTime.utc(2025, 8, 1),
      tags: List.unmodifiable(tags),
    );

Widget _buildScreen({
  required BusinessCard card,
  List<Tag> allTags = const [],
  List<Event> allEvents = const [],
  UpdateCardUseCase? useCase,
}) {
  final fakeCardRepo = _FakeCardRepository([card]);
  final fakeTagRepo = _FakeTagRepository(List.of(allTags));
  final fakeEventRepo = _FakeEventRepository(List.of(allEvents));
  final effectiveUseCase = useCase ??
      UpdateCardUseCase(
        cardRepository: fakeCardRepo,
        tagRepository: fakeTagRepo,
        eventRepository: fakeEventRepo,
        storage: _NoopStorage(),
      );

  return ProviderScope(
    overrides: [
      cardByIdProvider(card.id).overrideWith((_) async => card),
      cardListProvider.overrideWith((_) async => [card]),
      tagRepositoryProvider.overrideWith((_) async => fakeTagRepo),
      eventRepositoryProvider.overrideWith((_) async => fakeEventRepo),
      updateCardUseCaseProvider.overrideWith((_) async => effectiveUseCase),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: CardEditScreen(cardId: card.id),
    ),
  );
}

// Helper to scroll down in the ListView
Future<void> scrollDown(WidgetTester tester, {double pixels = 500}) async {
  await tester.fling(
    find.byType(Scrollable).first,
    Offset(0, -pixels),
    1000,
  );
  await tester.pumpAndSettle();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('CardEditScreen — loading and rendering', () {
    testWidgets('shows loading indicator before card data arrives',
        (tester) async {
      // We can't easily intercept the future in the middle, but we can verify
      // the screen at least renders without crashing once data is available.
      await tester.pumpWidget(_buildScreen(card: _makeCard()));
      // Allow futures to complete
      await tester.pump();
      await tester.pump();
      expect(find.text('カードを編集'), findsOneWidget);
    });

    testWidgets('renders card displayName in text field', (tester) async {
      final card = _makeCard(displayName: '田中花子');
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      expect(
        find.widgetWithText(TextField, '田中花子', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('renders memo in text field', (tester) async {
      final card = _makeCard(memo: '素敵な人');
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 1000);
      expect(find.text('素敵な人'), findsOneWidget);
    });

    testWidgets('shows 保存 button in AppBar actions', (tester) async {
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('appbar_save_button')), findsOneWidget);
    });

    testWidgets('shows 保存 ElevatedButton in body', (tester) async {
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      expect(find.byKey(const Key('save_button')), findsOneWidget);
    });

    testWidgets('shows field labels', (tester) async {
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      expect(find.text('表示名', skipOffstage: false), findsOneWidget);
      expect(find.text('X アカウント', skipOffstage: false), findsOneWidget);
    });

    testWidgets('populates snsLinks starting with @ as X handle',
        (tester) async {
      final card = _makeCard(snsLinks: ['@alice', 'https://example.com']);
      await tester.pumpWidget(_buildScreen(card: card));
      await tester.pump();
      await tester.pump();
      // The X handle row appears after scrolling a bit; verify the row is
      // built by checking its delete icon is present.
      await scrollDown(tester, pixels: 300);
      expect(find.byIcon(Icons.delete_outline), findsWidgets);
    });

    testWidgets('shows existing event chips', (tester) async {
      final event = const Event(id: 'ev1', name: 'コミケ106');
      final card = _makeCard(events: [event]);
      await tester.pumpWidget(_buildScreen(card: card, allEvents: [event]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      expect(find.text('コミケ106'), findsOneWidget);
    });

    testWidgets('shows existing tag chips', (tester) async {
      final tag = const Tag(id: 't1', name: 'Vtuber');
      final card = _makeCard(tags: [tag]);
      await tester.pumpWidget(_buildScreen(card: card, allTags: [tag]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      expect(find.text('Vtuber'), findsOneWidget);
    });
  });

  group('CardEditScreen — save flow', () {
    testWidgets('editing displayName and tapping 保存 pops with true',
        (tester) async {
      final card = _makeCard(displayName: '元の名前');
      bool? popResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider(card.id).overrideWith((_) async => card),
            cardListProvider.overrideWith((_) async => [card]),
            tagRepositoryProvider.overrideWith(
                (_) async => _FakeTagRepository([])),
            eventRepositoryProvider.overrideWith(
                (_) async => _FakeEventRepository([])),
            updateCardUseCaseProvider.overrideWith(
              (_) async => UpdateCardUseCase(
                cardRepository: _FakeCardRepository([card]),
                tagRepository: _FakeTagRepository([]),
                eventRepository: _FakeEventRepository([]),
                storage: _NoopStorage(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  popResult = await Navigator.of(ctx).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => CardEditScreen(cardId: card.id),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      // Open the edit screen
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      // Wait for cardByIdProvider to resolve
      await tester.pump();

      // Scroll display name into view first
      await scrollDown(tester, pixels: 100);
      // Edit the displayName field
      await tester.enterText(
          find.widgetWithText(TextField, '元の名前'), '新しい名前');
      await tester.pump();

      // Scroll to the save button
      await scrollDown(tester, pixels: 2000);

      // Tap save
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();

      expect(popResult, isTrue);
    });

    testWidgets('tapping AppBar 保存 also saves and pops', (tester) async {
      final card = _makeCard(displayName: 'テスト');
      bool? popResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider(card.id).overrideWith((_) async => card),
            cardListProvider.overrideWith((_) async => [card]),
            tagRepositoryProvider.overrideWith(
                (_) async => _FakeTagRepository([])),
            eventRepositoryProvider.overrideWith(
                (_) async => _FakeEventRepository([])),
            updateCardUseCaseProvider.overrideWith(
              (_) async => UpdateCardUseCase(
                cardRepository: _FakeCardRepository([card]),
                tagRepository: _FakeTagRepository([]),
                eventRepository: _FakeEventRepository([]),
                storage: _NoopStorage(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  popResult = await Navigator.of(ctx).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => CardEditScreen(cardId: card.id),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump();

      // Tap AppBar 保存 button
      await tester.tap(find.byKey(const Key('appbar_save_button')));
      await tester.pumpAndSettle();

      expect(popResult, isTrue);
    });
  });

  group('CardEditScreen — tag picker', () {
    testWidgets('opens tag picker sheet on button tap', (tester) async {
      final tag = const Tag(id: 't1', name: 'Vtuber');
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card, allTags: [tag]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      expect(find.text('タグを選択'), findsOneWidget);
      expect(find.text('Vtuber'), findsOneWidget);
    });

    testWidgets('selecting a tag from sheet shows chip on screen',
        (tester) async {
      final tag = const Tag(id: 't1', name: 'コスプレ');
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card, allTags: [tag]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('コスプレ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('コスプレ'), findsOneWidget);
    });
  });

  group('CardEditScreen — event picker', () {
    testWidgets('opens event picker sheet on button tap', (tester) async {
      final event = const Event(id: 'ev1', name: 'にじフェス');
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card, allEvents: [event]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      expect(find.text('イベントを選択'), findsOneWidget);
      expect(find.text('にじフェス'), findsOneWidget);
    });

    testWidgets('selecting an event and tapping 完了 shows event chip',
        (tester) async {
      final event = const Event(id: 'ev1', name: 'コミケ102');
      final card = _makeCard();
      await tester.pumpWidget(_buildScreen(card: card, allEvents: [event]));
      await tester.pump();
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_item_ev1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_done')));
      await tester.pumpAndSettle();
      expect(find.text('コミケ102'), findsOneWidget);
    });
  });

  group('CardEditScreen — unsaved changes guard', () {
    testWidgets('close button without changes pops without dialog',
        (tester) async {
      final card = _makeCard();
      bool screenPopped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider(card.id).overrideWith((_) async => card),
            cardListProvider.overrideWith((_) async => [card]),
            tagRepositoryProvider.overrideWith(
                (_) async => _FakeTagRepository([])),
            eventRepositoryProvider.overrideWith(
                (_) async => _FakeEventRepository([])),
            updateCardUseCaseProvider.overrideWith(
              (_) async => UpdateCardUseCase(
                cardRepository: _FakeCardRepository([card]),
                tagRepository: _FakeTagRepository([]),
                eventRepository: _FakeEventRepository([]),
                storage: _NoopStorage(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  await Navigator.of(ctx).push(
                    MaterialPageRoute(
                      builder: (_) => CardEditScreen(cardId: card.id),
                    ),
                  );
                  screenPopped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump();

      // Tap close without making any changes
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Should have popped without showing the dialog
      expect(screenPopped, isTrue);
      expect(find.text('変更を破棄しますか?'), findsNothing);
    });

    testWidgets('close button with dirty changes shows discard dialog',
        (tester) async {
      final card = _makeCard(displayName: '元の名前');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider(card.id).overrideWith((_) async => card),
            cardListProvider.overrideWith((_) async => [card]),
            tagRepositoryProvider.overrideWith(
                (_) async => _FakeTagRepository([])),
            eventRepositoryProvider.overrideWith(
                (_) async => _FakeEventRepository([])),
            updateCardUseCaseProvider.overrideWith(
              (_) async => UpdateCardUseCase(
                cardRepository: _FakeCardRepository([card]),
                tagRepository: _FakeTagRepository([]),
                eventRepository: _FakeEventRepository([]),
                storage: _NoopStorage(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute(
                    builder: (_) => CardEditScreen(cardId: card.id),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.pump();

      // Scroll the displayName field into view
      await scrollDown(tester, pixels: 100);
      // Make a change
      await tester.enterText(
          find.widgetWithText(TextField, '元の名前'), '変更後');
      await tester.pump();

      // Tap close
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('変更を破棄しますか?'), findsOneWidget);
    });
  });

  group('CardEditScreen — not found state', () {
    testWidgets('shows error when card is null', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider('missing').overrideWith((_) async => null),
            cardListProvider.overrideWith((_) async => []),
            tagRepositoryProvider.overrideWith(
                (_) async => _FakeTagRepository([])),
            eventRepositoryProvider.overrideWith(
                (_) async => _FakeEventRepository([])),
            updateCardUseCaseProvider.overrideWith(
              (_) async => UpdateCardUseCase(
                cardRepository: _FakeCardRepository([]),
                tagRepository: _FakeTagRepository([]),
                eventRepository: _FakeEventRepository([]),
                storage: _NoopStorage(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const CardEditScreen(cardId: 'missing'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('カードが見つかりません'), findsOneWidget);
    });
  });
}
