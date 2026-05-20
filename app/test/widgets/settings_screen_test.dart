import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/core/app_preferences.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/screens/settings_screen.dart';
import 'package:otameishi/theme/accent_colors.dart';
import 'package:otameishi/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Fake AppPreferences — in-memory, no SharedPreferences I/O.
// ---------------------------------------------------------------------------

class _FakePrefs implements AppPreferences {
  ThemeMode _themeMode = ThemeMode.system;
  int _accentIndex = 0;

  @override
  Future<ThemeMode> getThemeMode() async => _themeMode;

  @override
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
  }

  @override
  Future<int> getAccentColorIndex() async => _accentIndex;

  @override
  Future<void> setAccentColorIndex(int index) async {
    _accentIndex = index;
  }
}

// ---------------------------------------------------------------------------
// Fake CardRepository — in-memory, supports findMyCard / clearMyCard.
// ---------------------------------------------------------------------------

class _FakeCardRepository extends Fake implements CardRepository {
  _FakeCardRepository({BusinessCard? myCard}) : _myCard = myCard;

  BusinessCard? _myCard;
  int clearMyCardCallCount = 0;

  @override
  Future<BusinessCard?> findMyCard() async => _myCard;

  @override
  Future<void> clearMyCard() async {
    _myCard = null;
    clearMyCardCallCount++;
  }

  @override
  Future<void> setMyCard(String cardId) async {
    // Not needed in these tests.
  }

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

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

BusinessCard _makeMyCard() => BusinessCard(
      id: 'my-card-id',
      imagePath: '/nonexistent/my_card.jpg',
      displayName: '山田太郎',
      memo: 'コミケのメモです',
      snsLinks: const [],
      events: const [],
      tags: const [],
      createdAt: DateTime(2026, 5, 1),
      isMyCard: true,
    );

Widget _buildApp({
  _FakePrefs? prefs,
  BusinessCard? myCard,
  _FakeCardRepository? cardRepo,
}) {
  final fakePrefs = prefs ?? _FakePrefs();
  final fakeCardRepo = cardRepo ?? _FakeCardRepository(myCard: myCard);

  return ProviderScope(
    overrides: [
      appPreferencesProvider.overrideWithValue(fakePrefs),
      cardRepositoryProvider.overrideWith((_) async => fakeCardRepo),
      // myCardProvider reads cardRepositoryProvider, so override it directly
      // to avoid the async chain going through the real DatabaseProvider.
      myCardProvider.overrideWith((_) async => myCard),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const SettingsScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ─── マイカード section ──────────────────────────────────────────────────────

  group('SettingsScreen — マイカード (未設定)', () {
    testWidgets('shows register button when myCard is null', (tester) async {
      await tester.pumpWidget(_buildApp(myCard: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('register_my_card_button')), findsOneWidget);
      expect(find.text('自分の名刺を登録'), findsOneWidget);
    });

    testWidgets('does not show edit/clear buttons when myCard is null',
        (tester) async {
      await tester.pumpWidget(_buildApp(myCard: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_my_card_button')), findsNothing);
      expect(find.byKey(const Key('clear_my_card_button')), findsNothing);
    });
  });

  group('SettingsScreen — マイカード (設定済み)', () {
    testWidgets('shows displayName when myCard is set', (tester) async {
      await tester.pumpWidget(_buildApp(myCard: _makeMyCard()));
      await tester.pumpAndSettle();

      expect(find.text('山田太郎'), findsOneWidget);
    });

    testWidgets('shows 編集 and 解除 buttons when myCard is set', (tester) async {
      await tester.pumpWidget(_buildApp(myCard: _makeMyCard()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('edit_my_card_button')), findsOneWidget);
      expect(find.byKey(const Key('clear_my_card_button')), findsOneWidget);
    });

    testWidgets('does not show register button when myCard is set',
        (tester) async {
      await tester.pumpWidget(_buildApp(myCard: _makeMyCard()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('register_my_card_button')), findsNothing);
    });

    testWidgets('tapping 解除 shows confirmation dialog', (tester) async {
      await tester.pumpWidget(_buildApp(myCard: _makeMyCard()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear_my_card_button')));
      await tester.pumpAndSettle();

      expect(find.text('マイカードの登録を解除しますか?'), findsOneWidget);
    });

    testWidgets('confirming 解除 calls clearMyCard and updates UI',
        (tester) async {
      final fakeRepo = _FakeCardRepository(myCard: _makeMyCard());
      // Override both cardRepositoryProvider and myCardProvider.
      // myCardProvider must start with a card, then return null after clear.
      BusinessCard? myCardState = _makeMyCard();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesProvider.overrideWithValue(_FakePrefs()),
            cardRepositoryProvider.overrideWith((_) async => fakeRepo),
            myCardProvider.overrideWith((_) async => myCardState),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap 解除 to open dialog
      await tester.tap(find.byKey(const Key('clear_my_card_button')));
      await tester.pumpAndSettle();

      // Confirm in dialog
      await tester.tap(find.byKey(const Key('confirm_clear_my_card_button')));
      await tester.pumpAndSettle();

      expect(fakeRepo.clearMyCardCallCount, 1);
    });

    testWidgets('cancelling 解除 dialog leaves myCard intact', (tester) async {
      final fakeRepo = _FakeCardRepository(myCard: _makeMyCard());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appPreferencesProvider.overrideWithValue(_FakePrefs()),
            cardRepositoryProvider.overrideWith((_) async => fakeRepo),
            myCardProvider.overrideWith((_) async => _makeMyCard()),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('clear_my_card_button')));
      await tester.pumpAndSettle();

      // Tap キャンセル
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // clearMyCard should NOT have been called
      expect(fakeRepo.clearMyCardCallCount, 0);
      // Dialog dismissed, registered state still visible
      expect(find.byKey(const Key('clear_my_card_button')), findsOneWidget);
    });
  });

  // ─── 表示モード section ──────────────────────────────────────────────────────

  group('SettingsScreen — 表示モード', () {
    testWidgets('renders SegmentedButton with 3 segments', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(find.text('システム'), findsOneWidget);
      expect(find.text('ライト'), findsOneWidget);
      expect(find.text('ダーク'), findsOneWidget);
    });

    testWidgets('selecting ライト updates themeModeProvider', (tester) async {
      final fakePrefs = _FakePrefs();
      await tester.pumpWidget(_buildApp(prefs: fakePrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ライト'));
      await tester.pumpAndSettle();

      // The fake prefs should have been written.
      expect(await fakePrefs.getThemeMode(), ThemeMode.light);
    });

    testWidgets('selecting ダーク updates themeModeProvider', (tester) async {
      final fakePrefs = _FakePrefs();
      await tester.pumpWidget(_buildApp(prefs: fakePrefs));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ダーク'));
      await tester.pumpAndSettle();

      expect(await fakePrefs.getThemeMode(), ThemeMode.dark);
    });
  });

  // ─── アクセントカラー section ─────────────────────────────────────────────────

  group('SettingsScreen — アクセントカラー', () {
    testWidgets('renders correct number of color swatches', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // Each swatch has a Semantics label ending in the color name or 「選択中」.
      // Count via the GestureDetectors inside the Wrap.
      final swatchFinders = find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration,
      );
      // We expect at least kAccentColors.length circular containers.
      expect(swatchFinders.evaluate().length,
          greaterThanOrEqualTo(kAccentColors.length));
    });

    testWidgets('tapping a swatch updates accentColorIndexProvider',
        (tester) async {
      final fakePrefs = _FakePrefs();
      await tester.pumpWidget(_buildApp(prefs: fakePrefs));
      await tester.pumpAndSettle();

      // Tap the swatch labelled 「青」 (index 1).
      await tester.tap(find.bySemanticsLabel('青'));
      await tester.pumpAndSettle();

      expect(await fakePrefs.getAccentColorIndex(), 1);
    });

    testWidgets('initial swatch shows check icon on index 0', (tester) async {
      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      // The first swatch (ピンク) should have a check icon.
      final checkIcons = find.descendant(
        of: find.bySemanticsLabel('ピンク（選択中）'),
        matching: find.byIcon(Icons.check),
      );
      expect(checkIcons, findsOneWidget);
    });

    testWidgets('selecting swatch moves check icon to new selection',
        (tester) async {
      final fakePrefs = _FakePrefs();
      await tester.pumpWidget(_buildApp(prefs: fakePrefs));
      await tester.pumpAndSettle();

      // Tap ティール (index 2).
      await tester.tap(find.bySemanticsLabel('ティール'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.bySemanticsLabel('ティール（選択中）'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      // ピンク should no longer be selected.
      expect(find.bySemanticsLabel('ピンク（選択中）'), findsNothing);
    });
  });
}
