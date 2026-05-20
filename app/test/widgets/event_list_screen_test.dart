import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/screens/event_list_screen.dart';
import 'package:otameishi/theme/app_theme.dart';
import 'package:table_calendar/table_calendar.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEventRepository extends Fake implements EventRepository {
  _FakeEventRepository(this._items);

  final List<Event> _items;

  @override
  Future<List<Event>> findAll({bool orderByDateDesc = true}) async =>
      List.unmodifiable(_items);

  @override
  Future<Event?> findById(String id) async => null;

  @override
  Future<List<Event>> findByDateRange(DateTime from, DateTime to) async => [];

  @override
  Future<void> insert(Event event) async {}

  @override
  Future<void> update(Event event) async {}

  @override
  Future<void> delete(String id) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildApp(List<Event> items) {
  return ProviderScope(
    overrides: [
      eventRepositoryProvider.overrideWith((_) async => _FakeEventRepository(items)),
      eventListProvider.overrideWith(
        (_) async => List.unmodifiable(items),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const EventListScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  group('EventListScreen — list view', () {
    testWidgets('shows empty state when no events', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      expect(find.text('まだイベントがありません'), findsOneWidget);
    });

    testWidgets('shows event names in list', (tester) async {
      final events = [
        const Event(id: '1', name: 'コミケ106'),
        const Event(id: '2', name: 'VTuberフェス'),
      ];
      await tester.pumpWidget(_buildApp(events));
      await tester.pumpAndSettle();

      expect(find.text('コミケ106'), findsOneWidget);
      expect(find.text('VTuberフェス'), findsOneWidget);
    });

    testWidgets('has AppBar title "イベント"', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      expect(find.text('イベント'), findsOneWidget);
    });

    testWidgets('FAB is present', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('search bar is present', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('list/calendar toggle buttons are present', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      // Two IconButtons in AppBar actions
      expect(find.byIcon(Icons.list), findsOneWidget);
      expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);
    });
  });

  group('EventListScreen — search filtering', () {
    final events = [
      const Event(id: '1', name: 'コミケ106'),
      const Event(id: '2', name: 'VTuberフェス'),
      const Event(id: '3', name: 'ライブイベント'),
    ];

    testWidgets('filtering by name hides non-matching events', (tester) async {
      await tester.pumpWidget(_buildApp(events));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'コミケ');
      // Wait for debounce (200ms) + frame
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('コミケ106'), findsOneWidget);
      expect(find.text('VTuberフェス'), findsNothing);
      expect(find.text('ライブイベント'), findsNothing);
    });

    testWidgets('clearing search restores all events', (tester) async {
      await tester.pumpWidget(_buildApp(events));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'コミケ');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('コミケ106'), findsOneWidget);
      expect(find.text('VTuberフェス'), findsOneWidget);
      expect(find.text('ライブイベント'), findsOneWidget);
    });

    testWidgets('shows no-results empty state when filter matches nothing',
        (tester) async {
      await tester.pumpWidget(_buildApp(events));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzznomatch');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('該当するイベントがありません'), findsOneWidget);
    });
  });

  group('EventListScreen — calendar toggle', () {
    testWidgets('switches to calendar view on calendar icon tap', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();

      // TableCalendar<Event> is rendered — verify via widget predicate
      expect(
        find.byWidgetPredicate((w) => w is TableCalendar),
        findsOneWidget,
      );
    });

    testWidgets('switches back to list view on list icon tap', (tester) async {
      await tester.pumpWidget(_buildApp([]));
      await tester.pumpAndSettle();

      // Switch to calendar
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();

      // Switch back to list
      await tester.tap(find.byIcon(Icons.list_outlined));
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is TableCalendar),
        findsNothing,
      );
    });
  });
}
