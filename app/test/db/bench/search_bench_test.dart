// ignore_for_file: avoid_print
@Tags(['bench'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/search_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/event.dart';

import '../db_test_helper.dart';

const int _cardCount = 5000;
const Duration _searchTarget = Duration(seconds: 1);

void main() {
  group('Search benchmark (5k cards)', () {
    late Database db;
    late SqliteSearchRepository searchRepo;

    setUpAll(() async {
      db = await openTestDatabase();
      await _seedDatabase(db);
      searchRepo = SqliteSearchRepository(db);
    });

    tearDownAll(() async {
      await db.close();
    });

    test('full-text search completes in under 1 second', () async {
      final stopwatch = Stopwatch()..start();
      final results = await searchRepo.search('test');
      stopwatch.stop();

      print(
        'search("test") -> ${results.length} results in ${stopwatch.elapsedMilliseconds}ms',
      );

      expect(
        stopwatch.elapsed,
        lessThan(_searchTarget),
        reason:
            'FTS search across $_cardCount cards must complete in <1s '
            '(got ${stopwatch.elapsedMilliseconds}ms)',
      );
    });

    test('Japanese FTS search completes in under 1 second', () async {
      final stopwatch = Stopwatch()..start();
      final results = await searchRepo.search('イベント');
      stopwatch.stop();

      print(
        'search("イベント") -> ${results.length} results in ${stopwatch.elapsedMilliseconds}ms',
      );

      expect(
        stopwatch.elapsed,
        lessThan(_searchTarget),
        reason:
            'Japanese FTS search across $_cardCount cards must complete in <1s '
            '(got ${stopwatch.elapsedMilliseconds}ms)',
      );
    });
  });
}

/// Seeds [db] with [_cardCount] synthetic cards spread across 10 events and 20 tags.
///
/// Cards are inserted directly via raw SQL inside transactions (bypassing the
/// repository layer) so the FTS triggers fire at insert time just as they would
/// in production.
Future<void> _seedDatabase(Database db) async {
  final eventRepo = SqliteEventRepository(db);
  final tagRepo = SqliteTagRepository(db);

  // Create events.
  final events = <Event>[];
  for (var i = 0; i < 10; i++) {
    final event = Event(
      id: 'ev_$i',
      name: 'イベント$i',
      date: DateTime.utc(2026, (i % 12) + 1, 1),
      memo: i.isEven ? 'test event $i' : null,
    );
    await eventRepo.insert(event);
    events.add(event);
  }

  // Create tags.
  final tagIds = <String>[];
  final tagNames = [
    'Vtuber', 'コス', '絵描き', 'サークル', '同担',
    '学マス', '推し活', 'ライブ', 'test_tag', 'コミケ',
    'にじさんじ', 'ホロライブ', 'オフ会', 'グッズ', '写真',
    'アート', 'ゲーム', 'アニメ', 'マンガ', '音楽',
  ];
  for (final name in tagNames) {
    final tag = await tagRepo.findOrCreate(name);
    tagIds.add(tag.id);
  }

  // Insert cards in batches within transactions.
  const batchSize = 100;
  final base = DateTime.utc(2026, 1, 1);

  for (var batch = 0; batch < _cardCount ~/ batchSize; batch++) {
    await db.transaction((txn) async {
      for (var i = 0; i < batchSize; i++) {
        final idx = batch * batchSize + i;
        final cardId = 'card_$idx';
        final eventId = events[idx % events.length].id;

        final displayName = idx % 3 == 0
            ? 'testuser_$idx'
            : idx % 3 == 1
                ? 'ユーザー$idx'
                : 'User$idx';

        final memo = idx % 5 == 0 ? 'test memo $idx' : '通常メモ $idx';

        await txn.insert('business_cards', {
          'id': cardId,
          'image_path': '/images/$cardId.jpg',
          'display_name': displayName,
          'sns_links_json': '[]',
          'memo': memo,
          'created_at': base.add(Duration(minutes: idx)).toIso8601String(),
        });

        // Populate junction table for many-to-many event linkage.
        await txn.insert(
          'business_card_events',
          {'card_id': cardId, 'event_id': eventId},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );

        final tag1Id = tagIds[idx % tagIds.length];
        final tag2Id = tagIds[(idx + 1) % tagIds.length];

        await txn.insert(
          'business_card_tags',
          {'card_id': cardId, 'tag_id': tag1Id},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        if (tag1Id != tag2Id) {
          await txn.insert(
            'business_card_tags',
            {'card_id': cardId, 'tag_id': tag2Id},
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
  }

  print('Seeded $_cardCount synthetic cards.');
}
