import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/screens/home_screen.dart';
import 'package:otameishi/theme/app_theme.dart';

// ─── Test data ────────────────────────────────────────────────────────────────

BusinessCard _makeCard(String id, String name) => BusinessCard(
      id: id,
      imagePath: '/nonexistent/$id.jpg',
      displayName: name,
      snsLinks: const [],
      memo: null,
      events: const [],
      tags: const [],
      createdAt: DateTime(2025, 8, 1),
    );

final _testCards = [
  _makeCard('card-1', 'テストユーザーA'),
  _makeCard('card-2', 'テストユーザーB'),
  _makeCard('card-3', 'テストユーザーC'),
];

// ─── App builder ──────────────────────────────────────────────────────────────

/// Wraps [HomeScreen] with a [ProviderScope] that stubs [cardListProvider]
/// with [cards].  Also registers a minimal route for `/card` so navigation
/// assertions can verify the destination.
Widget _buildApp({List<BusinessCard> cards = const []}) {
  return ProviderScope(
    overrides: [
      cardListProvider.overrideWith((_) async => cards),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: (settings) {
        if (settings.name == '/card') {
          final id = settings.arguments as String;
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('カード詳細')),
              body: Center(child: Text('card:$id')),
            ),
          );
        }
        return null;
      },
      home: const HomeScreen(),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  // ── Toggle button presence ────────────────────────────────────────────────

  group('HomeScreen — view toggle button', () {
    testWidgets('shows grid_view_rounded icon in default list mode',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.grid_view_rounded), findsOneWidget);
      expect(find.byIcon(Icons.view_list_rounded), findsNothing);
    });

    testWidgets('toggle button has correct tooltip in list mode',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      final iconButton = find.byIcon(Icons.grid_view_rounded);
      expect(iconButton, findsOneWidget);

      // Long-press to show tooltip
      await tester.longPress(iconButton);
      await tester.pumpAndSettle();

      expect(find.text('ギャラリー表示'), findsOneWidget);
    });
  });

  // ── Switching to gallery mode ─────────────────────────────────────────────

  group('HomeScreen — switching to gallery mode', () {
    testWidgets('tapping toggle switches from ListView to GridView',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      // Initial state: ListView present, GridView absent
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);

      // Tap the toggle
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      // After toggle: GridView present, ListView absent
      expect(find.byType(GridView), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('icon changes to view_list_rounded in gallery mode',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.view_list_rounded), findsOneWidget);
      expect(find.byIcon(Icons.grid_view_rounded), findsNothing);
    });

    testWidgets('toggle button tooltip changes to リスト表示 in gallery mode',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      await tester.longPress(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      expect(find.text('リスト表示'), findsOneWidget);
    });
  });

  // ── Switching back to list mode ───────────────────────────────────────────

  group('HomeScreen — switching back to list mode', () {
    testWidgets('tapping toggle twice returns to ListView', (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      // Toggle to gallery
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      // Toggle back to list
      await tester.tap(find.byIcon(Icons.view_list_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });
  });

  // ── Gallery tile rendering ────────────────────────────────────────────────

  group('HomeScreen — gallery tiles', () {
    testWidgets('gallery tiles show card display names', (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(find.text('テストユーザーA'), findsOneWidget);
      expect(find.text('テストユーザーB'), findsOneWidget);
    });

    testWidgets('tapping a gallery tile navigates to /card with card id',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: _testCards));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      // Tap the first visible tile by its display name
      await tester.tap(find.text('テストユーザーA'));
      await tester.pumpAndSettle();

      expect(find.text('card:card-1'), findsOneWidget);
    });
  });

  // ── Empty state ───────────────────────────────────────────────────────────

  group('HomeScreen — empty state', () {
    testWidgets('empty state shows in list mode when no cards', (tester) async {
      await tester.pumpWidget(_buildApp(cards: const []));
      await tester.pumpAndSettle();

      expect(find.text('まだ名刺がありません'), findsOneWidget);
    });

    testWidgets('empty state shows in gallery mode when no cards',
        (tester) async {
      await tester.pumpWidget(_buildApp(cards: const []));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();

      expect(find.text('まだ名刺がありません'), findsOneWidget);
    });
  });
}
