import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/screens/event_edit_screen.dart';
import 'package:otameishi/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeEventRepository extends Fake implements EventRepository {
  _FakeEventRepository([List<Event>? initial])
      : _store = [...?initial];

  final List<Event> _store;
  final List<Event> inserted = [];
  final List<Event> updated = [];
  final List<String> deleted = [];

  @override
  Future<List<Event>> findAll({bool orderByDateDesc = true}) async =>
      List.unmodifiable(_store);

  @override
  Future<Event?> findById(String id) async {
    try {
      return _store.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Event>> findByDateRange(DateTime from, DateTime to) async => [];

  @override
  Future<void> insert(Event event) async {
    inserted.add(event);
    _store.add(event);
  }

  @override
  Future<void> update(Event event) async {
    updated.add(event);
    final i = _store.indexWhere((e) => e.id == event.id);
    if (i >= 0) _store[i] = event;
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    _store.removeWhere((e) => e.id == id);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildApp({
  String? eventId,
  required _FakeEventRepository repo,
}) {
  return ProviderScope(
    overrides: [
      eventRepositoryProvider.overrideWith((_) async => repo),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja'), Locale('en')],
      routes: {
        '/': (_) => EventEditScreen(eventId: eventId),
      },
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

  group('EventEditScreen — new event', () {
    late _FakeEventRepository repo;

    setUp(() => repo = _FakeEventRepository());

    testWidgets('renders "イベントを追加" title', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('イベントを追加'), findsOneWidget);
    });

    testWidgets('shows name field and save button', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('イベント名 *'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('delete button is hidden for new event', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('削除'), findsNothing);
    });

    testWidgets('shows validation error when name is empty', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('イベント名を入力してください'), findsOneWidget);
      expect(repo.inserted, isEmpty);
    });

    testWidgets('shows validation error for whitespace-only name', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '   ');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('イベント名を入力してください'), findsOneWidget);
    });

    testWidgets('save button inserts event and pops', (tester) async {
      bool popped = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ja'), Locale('en')],
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<dynamic>(
                    MaterialPageRoute(
                      builder: (_) => const EventEditScreen(eventId: null),
                    ),
                  );
                  if (result != null) popped = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, 'コミケ106');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.inserted, hasLength(1));
      expect(repo.inserted.first.name, 'コミケ106');
      expect(popped, isTrue);
    });

    testWidgets('name field has min 44dp touch target', (tester) async {
      await tester.pumpWidget(_buildApp(repo: repo));
      await tester.pumpAndSettle();

      final field = tester.getRect(find.byType(TextFormField).first);
      expect(field.height, greaterThanOrEqualTo(44));
    });
  });

  group('EventEditScreen — edit event', () {
    const existingId = 'event-1';
    final existingEvent = Event(
      id: existingId,
      name: 'コミケ104',
      date: DateTime(2023, 8, 11),
      memo: 'テスト',
    );
    late _FakeEventRepository repo;

    setUp(() => repo = _FakeEventRepository([existingEvent]));

    testWidgets('renders "イベントを編集" title', (tester) async {
      await tester.pumpWidget(_buildApp(eventId: existingId, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('イベントを編集'), findsOneWidget);
    });

    testWidgets('pre-fills name and memo from existing event', (tester) async {
      await tester.pumpWidget(_buildApp(eventId: existingId, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('コミケ104'), findsOneWidget);
      expect(find.text('テスト'), findsOneWidget);
    });

    testWidgets('delete button is visible in edit mode', (tester) async {
      await tester.pumpWidget(_buildApp(eventId: existingId, repo: repo));
      await tester.pumpAndSettle();

      expect(find.text('削除'), findsOneWidget);
    });

    testWidgets('save updates event', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ja'), Locale('en')],
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(context).push<dynamic>(
                  MaterialPageRoute(
                    builder: (_) =>
                        const EventEditScreen(eventId: existingId),
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

      final nameField = find.byType(TextFormField).first;
      await tester.enterText(nameField, 'コミケ104改');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(repo.updated, hasLength(1));
      expect(repo.updated.first.name, 'コミケ104改');
    });

    testWidgets('delete shows confirmation dialog', (tester) async {
      await tester.pumpWidget(_buildApp(eventId: existingId, repo: repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      expect(find.text('イベントを削除しますか?'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
    });

    testWidgets('delete confirmed calls repo.delete', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            eventRepositoryProvider.overrideWith((_) async => repo),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: const [Locale('ja'), Locale('en')],
            routes: {
              '/': (_) => const EventEditScreen(eventId: existingId),
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('削除'));
      await tester.pumpAndSettle();

      // Confirm deletion in dialog
      await tester.tap(find.text('削除').last);
      await tester.pumpAndSettle();

      expect(repo.deleted, contains(existingId));
    });
  });
}
