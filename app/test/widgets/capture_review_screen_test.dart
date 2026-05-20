import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/screens/capture_review_screen.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/theme/app_theme.dart';
import 'package:otameishi/usecases/save_card_usecase.dart';

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

class _FakeSaveCardUseCase extends SaveCardUseCase {
  _FakeSaveCardUseCase()
      : super(
          cardRepository: _FakeCardRepository(),
          tagRepository: _FakeTagRepository([]),
          eventRepository: _FakeEventRepository([]),
        );

  @override
  Future<BusinessCard> execute(SaveCardInput input) async {
    return BusinessCard(
      id: 'fake-id',
      imagePath: input.draft.imagePath,
      snsLinks: const [],
      events: const [],
      tags: const [],
      createdAt: DateTime.now(),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CardDraft _makeDraft() => const CardDraft(imagePath: '/nonexistent/card.jpg');

Widget _buildScreen({
  List<Tag> tags = const [],
  List<Event> events = const [],
}) {
  final fakeTagRepo = _FakeTagRepository(List.of(tags));
  final fakeEventRepo = _FakeEventRepository(List.of(events));
  final fakeSaveUseCase = _FakeSaveCardUseCase();

  return ProviderScope(
    overrides: [
      tagRepositoryProvider.overrideWith((_) async => fakeTagRepo),
      eventRepositoryProvider.overrideWith((_) async => fakeEventRepo),
      saveCardUseCaseProvider.overrideWith((_) async => fakeSaveUseCase),
      cardListProvider.overrideWith((_) async => []),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: CaptureReviewScreen(draft: _makeDraft()),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Helper: fling the main ListView downward to build lazy items, then settle
  Future<void> scrollDown(WidgetTester tester, {double pixels = 500}) async {
    // Use fling so the ListView actually builds off-screen items
    await tester.fling(
      find.byType(Scrollable).first,
      Offset(0, -pixels),
      1000,
    );
    await tester.pumpAndSettle();
  }

  group('CaptureReviewScreen v3 — tag section', () {
    testWidgets('shows add-tag button when no tags selected', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      // Scroll down to build lazy ListView items below the initial viewport
      await scrollDown(tester, pixels: 2000);
      expect(find.byKey(const Key('add_tag_button')), findsOneWidget);
    });

    testWidgets('opens tag picker sheet on button tap', (tester) async {
      await tester.pumpWidget(_buildScreen(
        tags: [const Tag(id: '1', name: 'Vtuber')],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      expect(find.text('タグを選択'), findsOneWidget);
      expect(find.text('Vtuber'), findsOneWidget);
    });

    testWidgets('selecting a tag from sheet and tapping 完了 shows chip',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        tags: [const Tag(id: '1', name: 'Vtuber')],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      // Check the Vtuber checkbox
      await tester.tap(find.text('Vtuber'));
      await tester.pumpAndSettle();
      // Tap 完了
      await tester.tap(find.text('完了 (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Vtuber'), findsOneWidget);
    });

    testWidgets('entering new tag name shows create-row in sheet', (tester) async {
      await tester.pumpWidget(_buildScreen(
        tags: [const Tag(id: '1', name: 'Vtuber')],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      // Type a new tag name that doesn't exist
      await tester.enterText(find.byKey(const Key('tag_search_field')), '推し活');
      await tester.pumpAndSettle();
      expect(find.textContaining('推し活'), findsWidgets);
      expect(find.textContaining('新しいタグ'), findsOneWidget);
    });

    testWidgets('selected tag chip can be removed via onDeleted', (tester) async {
      await tester.pumpWidget(_buildScreen(
        tags: [const Tag(id: '1', name: 'Vtuber')],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      // Open sheet, select tag, close
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vtuber'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了 (1)'));
      await tester.pumpAndSettle();
      // Tag chip is visible; remove it via the delete icon
      expect(find.text('Vtuber'), findsOneWidget);
      // Chip delete icon (Icons.cancel) should be present
      final cancelIcon = find.descendant(
        of: find.byType(Chip),
        matching: find.byIcon(Icons.cancel),
      );
      await tester.tap(cancelIcon.first);
      await tester.pumpAndSettle();
      expect(find.byType(Chip), findsNothing);
    });
  });

  group('CaptureReviewScreen v4 — event section (multi-select)', () {
    testWidgets('shows add-event button when no events selected', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      // Scroll to build the event section
      await scrollDown(tester, pixels: 500);
      expect(find.byKey(const Key('select_event_button')), findsOneWidget);
    });

    testWidgets('opens event picker sheet on button tap', (tester) async {
      await tester.pumpWidget(_buildScreen(
        events: [const Event(id: 'ev1', name: 'コミケ106')],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      expect(find.text('イベントを選択'), findsOneWidget);
      expect(find.text('コミケ106'), findsOneWidget);
    });

    testWidgets('selecting 2 events and tapping 完了 shows 2 chips on review screen',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        events: [
          const Event(id: 'ev1', name: 'コミケ106'),
          const Event(id: 'ev2', name: 'にじフェス2026'),
        ],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      // Check both events
      await tester.tap(find.byKey(const Key('event_picker_item_ev1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_item_ev2')));
      await tester.pumpAndSettle();
      // Confirm
      await tester.tap(find.text('完了 (2)'));
      await tester.pumpAndSettle();
      // Both chips should be on the main screen
      expect(find.byKey(const Key('event_chip_ev1')), findsOneWidget);
      expect(find.byKey(const Key('event_chip_ev2')), findsOneWidget);
      expect(find.text('コミケ106'), findsOneWidget);
      expect(find.text('にじフェス2026'), findsOneWidget);
    });

    testWidgets('removing an event chip via × unselects that event', (tester) async {
      await tester.pumpWidget(_buildScreen(
        events: [
          const Event(id: 'ev1', name: 'コミケ106'),
          const Event(id: 'ev2', name: 'にじフェス2026'),
        ],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      // Select both events
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_item_ev1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_item_ev2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了 (2)'));
      await tester.pumpAndSettle();
      // Remove ev1 chip
      final ev1Chip = find.byKey(const Key('event_chip_ev1'));
      expect(ev1Chip, findsOneWidget);
      final cancelIcon = find.descendant(
        of: ev1Chip,
        matching: find.byIcon(Icons.cancel),
      );
      await tester.tap(cancelIcon.first);
      await tester.pumpAndSettle();
      // ev1 gone, ev2 remains
      expect(find.byKey(const Key('event_chip_ev1')), findsNothing);
      expect(find.byKey(const Key('event_chip_ev2')), findsOneWidget);
    });

    testWidgets('re-opening picker shows previously-selected events pre-checked',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        events: [
          const Event(id: 'ev1', name: 'コミケ106'),
          const Event(id: 'ev2', name: 'にじフェス2026'),
        ],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      // First open: select ev1
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_picker_item_ev1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了 (1)'));
      await tester.pumpAndSettle();
      // Re-open picker: ev1 should be pre-checked (value == true)
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      final ev1Tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('event_picker_item_ev1')),
      );
      expect(ev1Tile.value, isTrue);
      final ev2Tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('event_picker_item_ev2')),
      );
      expect(ev2Tile.value, isFalse);
    });

    testWidgets('選択をクリア clears multi-selection without closing sheet',
        (tester) async {
      await tester.pumpWidget(_buildScreen(
        events: [
          const Event(id: 'ev1', name: 'コミケ106'),
        ],
      ));
      await tester.pump();
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('select_event_button')));
      await tester.pumpAndSettle();
      // Select ev1
      await tester.tap(find.byKey(const Key('event_picker_item_ev1')));
      await tester.pumpAndSettle();
      // Tap 選択をクリア
      await tester.tap(find.text('選択をクリア'));
      await tester.pumpAndSettle();
      // Sheet still open, ev1 should be unchecked
      final ev1Tile = tester.widget<CheckboxListTile>(
        find.byKey(const Key('event_picker_item_ev1')),
      );
      expect(ev1Tile.value, isFalse);
      // Confirm button shows no count
      expect(find.text('完了'), findsOneWidget);
    });
  });

  group('CaptureReviewScreen v3 — save flow', () {
    testWidgets('shows confirm dialog when pending new tags exist', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      await scrollDown(tester, pixels: 2000);
      // Open tag sheet, type new tag, add it
      await tester.tap(find.byKey(const Key('add_tag_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('tag_search_field')), '新規タグ');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('新しいタグ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了 (1)'));
      await tester.pumpAndSettle();
      // Scroll to save button and tap
      await scrollDown(tester, pixels: 500);
      await tester.tap(find.byKey(const Key('save_button')));
      await tester.pumpAndSettle();
      expect(find.text('新しいタグを作成しますか?'), findsOneWidget);
      expect(find.text('作成して保存'), findsOneWidget);
      expect(find.text('キャンセル'), findsWidgets);
    });

    testWidgets('label section and v2 fields still present', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await tester.pump();
      // AppBar title always visible after single pump
      expect(find.text('内容を確認'), findsOneWidget);
      // Labels visible in the upper portion of the 800x600 test viewport
      expect(find.text('表示名', skipOffstage: false), findsOneWidget);
      // Use skipOffstage:false — the ListView may lazy-render past its viewport
      expect(find.text('X アカウント', skipOffstage: false), findsOneWidget);
    });
  });
}
