import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otameishi/core/providers.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/screens/tag_list_screen.dart';
import 'package:otameishi/theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Fakes / mocks
// ---------------------------------------------------------------------------

class _FakeTagRepository extends Fake implements TagRepository {
  _FakeTagRepository(this._items);

  final List<TagWithCount> _items;
  final List<String> deletedIds = [];

  @override
  Future<List<Tag>> findAll() async =>
      _items.map((e) => e.tag).toList(growable: false);

  @override
  Future<List<TagWithCount>> findAllWithCounts() async =>
      List.unmodifiable(_items);

  @override
  Future<Tag> findOrCreate(String name) async {
    final existing = _items.firstWhere(
      (e) => e.tag.name.toLowerCase() == name.toLowerCase(),
      orElse: () => TagWithCount(
        tag: Tag(id: 'new-id', name: name),
        cardCount: 0,
      ),
    );
    return existing.tag;
  }

  @override
  Future<void> insert(Tag tag) async {
    _items.add(TagWithCount(tag: tag, cardCount: 0));
  }

  @override
  Future<void> update(Tag tag) async {}

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    _items.removeWhere((e) => e.tag.id == id);
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildApp({
  required List<TagWithCount> items,
  _FakeTagRepository? repoOut,
}) {
  final repo = _FakeTagRepository(items);
  if (repoOut != null) {
    // We cannot assign to a final, so we rely on the same list reference.
  }

  return ProviderScope(
    overrides: [
      tagRepositoryProvider.overrideWith((_) async => repo),
      tagListWithCountsProvider.overrideWith((_) async => repo._items),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const TagListScreen(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('TagListScreen', () {
    testWidgets('renders AppBar with タグ管理 title', (tester) async {
      await tester.pumpWidget(_buildApp(items: []));
      await tester.pumpAndSettle();
      expect(find.text('タグ管理'), findsOneWidget);
    });

    testWidgets('shows add form with placeholder and counter', (tester) async {
      await tester.pumpWidget(_buildApp(items: []));
      await tester.pumpAndSettle();
      expect(find.text('新しいタグ名'), findsOneWidget);
      expect(find.text('追加'), findsOneWidget);
      expect(find.text('0 / 20'), findsOneWidget);
    });

    testWidgets('shows empty state when no tags', (tester) async {
      await tester.pumpWidget(_buildApp(items: []));
      await tester.pumpAndSettle();
      expect(find.text('タグがありません'), findsOneWidget);
      expect(find.text('名刺を保存するときにタグを追加できます'), findsOneWidget);
      expect(find.byIcon(Icons.label_outline), findsAtLeastNWidgets(1));
    });

    testWidgets('renders tag rows with name and usage count', (tester) async {
      final items = [
        TagWithCount(tag: const Tag(id: 'a', name: 'Vtuber'), cardCount: 12),
        TagWithCount(tag: const Tag(id: 'b', name: 'コス'), cardCount: 8),
      ];
      await tester.pumpWidget(_buildApp(items: items));
      await tester.pumpAndSettle();
      expect(find.text('Vtuber'), findsOneWidget);
      expect(find.text('12枚に使用中'), findsOneWidget);
      expect(find.text('コス'), findsOneWidget);
      expect(find.text('8枚に使用中'), findsOneWidget);
    });

    testWidgets('counter updates as user types', (tester) async {
      await tester.pumpWidget(_buildApp(items: []));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.pump();
      expect(find.text('3 / 20'), findsOneWidget);
    });

    testWidgets('追加 button disabled when field is empty', (tester) async {
      await tester.pumpWidget(_buildApp(items: []));
      await tester.pumpAndSettle();
      // The TextButton for 追加 should be disabled (no text in field).
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('追加'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('shows duplicate error inline', (tester) async {
      final items = [
        TagWithCount(
          tag: const Tag(id: 'a', name: 'Vtuber'),
          cardCount: 1,
        ),
      ];
      await tester.pumpWidget(_buildApp(items: items));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'vtuber');
      await tester.pump();
      expect(find.text('同じ名前のタグがすでにあります'), findsOneWidget);
    });

    testWidgets('delete icon has 44dp touch target', (tester) async {
      final items = [
        TagWithCount(tag: const Tag(id: 'a', name: 'Test'), cardCount: 0),
      ];
      await tester.pumpWidget(_buildApp(items: items));
      await tester.pumpAndSettle();
      // The SizedBox with the delete button key is the 44×44 touch target.
      final box = tester.widget<SizedBox>(
        find.byKey(const ValueKey('delete_btn_a')),
      );
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
    });

    testWidgets('delete dialog shows for tag not in use', (tester) async {
      final items = [
        TagWithCount(tag: const Tag(id: 'a', name: 'Test'), cardCount: 0),
      ];
      await tester.pumpWidget(_buildApp(items: items));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete_btn_a')));
      await tester.pumpAndSettle();
      expect(find.text('「Test」を削除しますか？'), findsOneWidget);
    });

    testWidgets('delete dialog shows card count when tag in use', (tester) async {
      final items = [
        TagWithCount(
          tag: const Tag(id: 'a', name: 'Test'),
          cardCount: 5,
        ),
      ];
      await tester.pumpWidget(_buildApp(items: items));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete_btn_a')));
      await tester.pumpAndSettle();
      expect(find.textContaining('5枚から削除されます'), findsOneWidget);
    });

    testWidgets('shows loading skeletons initially', (tester) async {
      // Use a Completer so the future stays pending without a live timer,
      // which would prevent the test from tearing down cleanly.
      final completer = Completer<List<TagWithCount>>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tagListWithCountsProvider.overrideWith(
              (_) => completer.future,
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const TagListScreen(),
          ),
        ),
      );
      // One frame: future still pending, skeleton should be visible.
      await tester.pump();
      expect(find.byKey(const ValueKey('tag_list_skeleton')), findsOneWidget);
      // Complete to allow cleanup.
      completer.complete([]);
      await tester.pumpAndSettle();
    });
  });
}
