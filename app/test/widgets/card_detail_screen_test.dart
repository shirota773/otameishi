import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/screens/card_detail_screen.dart';
import 'package:otameishi/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _kCardId = 'card-001';

BusinessCard _makeCard({List<Event> events = const []}) => BusinessCard(
      id: _kCardId,
      imagePath: '/nonexistent/card.jpg',
      displayName: 'テストユーザー',
      snsLinks: const [],
      memo: null,
      events: events,
      tags: const [Tag(id: 'tag-1', name: 'Vtuber')],
      createdAt: DateTime(2025, 8, 1),
    );

/// Wraps [CardDetailScreen] with providers that return [card] from
/// [cardByIdProvider].  The [cardListProvider] is stubbed to avoid hitting
/// the real DB.
Widget _buildApp(BusinessCard card) {
  return ProviderScope(
    overrides: [
      cardByIdProvider(card.id).overrideWith((_) async => card),
      cardListProvider.overrideWith((_) async => [card]),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      // Minimal onGenerateRoute so pushNamed('/card/edit') resolves without crash.
      onGenerateRoute: (settings) {
        if (settings.name == '/event') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('イベント詳細')),
              body: Center(child: Text('event:${settings.arguments}')),
            ),
          );
        }
        if (settings.name == '/card/edit') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('編集')),
              body: Center(child: Text('edit:${settings.arguments}')),
            ),
          );
        }
        return null;
      },
      home: CardDetailScreen(cardId: card.id),
    ),
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Scrolls down so off-viewport ListView items are built.
Future<void> _scrollDown(WidgetTester tester, {double pixels = 600}) async {
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
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  // ── Event section visibility ───────────────────────────────────────────────

  group('CardDetailScreen — event section', () {
    testWidgets('no event section rendered when card has 0 events',
        (tester) async {
      final card = _makeCard(events: const []);
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();

      // Use skipOffstage:false to check even lazy-built items.
      expect(find.text('イベント', skipOffstage: false), findsNothing);
      expect(find.byType(ActionChip, skipOffstage: false), findsNothing);
    });

    testWidgets('renders 1 chip with event name when card has 1 event',
        (tester) async {
      final card = _makeCard(events: const [
        Event(id: 'ev1', name: 'コミケ106'),
      ]);
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();
      await _scrollDown(tester);

      expect(find.text('イベント', skipOffstage: false), findsOneWidget);
      expect(find.byType(ActionChip, skipOffstage: false), findsNWidgets(1));
      expect(find.text('コミケ106', skipOffstage: false), findsOneWidget);
    });

    testWidgets('renders 2 chips when card has 2 events', (tester) async {
      final card = _makeCard(events: const [
        Event(id: 'ev1', name: 'コミケ106'),
        Event(id: 'ev2', name: 'VTuberフェス'),
      ]);
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();
      await _scrollDown(tester);

      expect(find.byType(ActionChip, skipOffstage: false), findsNWidgets(2));
      expect(find.text('コミケ106', skipOffstage: false), findsOneWidget);
      expect(find.text('VTuberフェス', skipOffstage: false), findsOneWidget);
    });

    testWidgets('tapping an event chip navigates to /event with event id',
        (tester) async {
      const eventId = 'ev-tap';
      final card = _makeCard(events: const [
        Event(id: eventId, name: 'ライブイベント'),
      ]);
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();
      await _scrollDown(tester);

      await tester.tap(find.text('ライブイベント', skipOffstage: false));
      await tester.pumpAndSettle();

      // The stub route renders 'event:<id>'
      expect(find.text('event:$eventId'), findsOneWidget);
    });
  });

  // ── 編集 button ───────────────────────────────────────────────────────────

  group('CardDetailScreen — 編集 AppBar button', () {
    testWidgets('edit IconButton is present in AppBar', (tester) async {
      final card = _makeCard();
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('tapping 編集 button navigates to /card/edit with card id',
        (tester) async {
      final card = _makeCard();
      await tester.pumpWidget(_buildApp(card));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // The stub route renders 'edit:<cardId>'
      expect(find.text('edit:${card.id}'), findsOneWidget);
    });

    testWidgets('returning true from edit route invalidates providers',
        (tester) async {
      // Track how many times cardByIdProvider is called by counting loads.
      var loadCount = 0;
      final card = _makeCard();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            cardByIdProvider(card.id).overrideWith((_) async {
              loadCount++;
              return card;
            }),
            cardListProvider.overrideWith((_) async => [card]),
          ],
          child: MaterialApp(
            onGenerateRoute: (settings) {
              if (settings.name == '/card/edit') {
                return MaterialPageRoute(
                  settings: settings,
                  builder: (ctx) => Scaffold(
                    body: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('完了'),
                    ),
                  ),
                );
              }
              return null;
            },
            home: CardDetailScreen(cardId: card.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final countAfterInitialLoad = loadCount;
      expect(countAfterInitialLoad, greaterThanOrEqualTo(1));

      // Navigate to edit stub and pop with true
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完了'));
      await tester.pumpAndSettle();

      // Provider was invalidated, so loadCount incremented again.
      expect(loadCount, greaterThan(countAfterInitialLoad));
    });
  });
}
