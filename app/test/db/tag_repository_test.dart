import 'package:flutter_test/flutter_test.dart';

import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/tag.dart';

import 'db_test_helper.dart';

void main() {
  group('SqliteTagRepository', () {
    late Database db;
    late SqliteTagRepository repo;

    setUp(() async {
      db = await openTestDatabase();
      repo = SqliteTagRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('findAll returns empty list initially', () async {
      expect(await repo.findAll(), isEmpty);
    });

    test('findOrCreate creates a new tag', () async {
      final tag = await repo.findOrCreate('Vtuber');
      expect(tag.name, 'Vtuber');
      expect(tag.id, isNotEmpty);
    });

    test('findOrCreate is idempotent for identical name', () async {
      final t1 = await repo.findOrCreate('コス');
      final t2 = await repo.findOrCreate('コス');
      expect(t1.id, t2.id);
      expect(t1.name, t2.name);
    });

    test('findOrCreate is case-insensitive for ASCII', () async {
      final t1 = await repo.findOrCreate('Vtuber');
      final t2 = await repo.findOrCreate('vtuber');
      expect(t1.id, t2.id);
    });

    test('findOrCreate is case-insensitive for mixed case', () async {
      final t1 = await repo.findOrCreate('VTUBER');
      final t2 = await repo.findOrCreate('vtuber');
      expect(t1.id, t2.id);
    });

    test('findAll returns all tags sorted by name', () async {
      await repo.findOrCreate('Z tag');
      await repo.findOrCreate('A tag');
      await repo.findOrCreate('M tag');

      final tags = await repo.findAll();
      expect(tags.map((t) => t.name).toList(), ['A tag', 'M tag', 'Z tag']);
    });

    test('delete removes the tag', () async {
      final tag = await repo.findOrCreate('削除対象');
      await repo.delete(tag.id);
      final all = await repo.findAll();
      expect(all.any((t) => t.id == tag.id), isFalse);
    });

    test('findOrCreate throws on blank name', () async {
      expect(() => repo.findOrCreate('  '), throwsArgumentError);
    });

    test('findAll returns unmodifiable list', () async {
      final tag = await repo.findOrCreate('test');
      final tags = await repo.findAll();
      expect(() => (tags as List<dynamic>).add(tag), throwsUnsupportedError);
    });

    test('multiple distinct tags are all retrievable', () async {
      await repo.findOrCreate('同担');
      await repo.findOrCreate('絵描き');
      await repo.findOrCreate('サークル');

      final tags = await repo.findAll();
      expect(tags.length, 3);
    });

    // -------------------------------------------------------------------------
    // insert
    // -------------------------------------------------------------------------

    test('insert persists a tag with a caller-supplied id', () async {
      const tag = Tag(id: 'fixed-id-001', name: '学マス');
      await repo.insert(tag);

      final all = await repo.findAll();
      expect(all.length, 1);
      expect(all.first.id, 'fixed-id-001');
      expect(all.first.name, '学マス');
    });

    test('insert trims whitespace from name', () async {
      const tag = Tag(id: 't1', name: '  コス  ');
      await repo.insert(tag);

      final all = await repo.findAll();
      expect(all.first.name, 'コス');
    });

    test('insert throws ArgumentError on blank name', () async {
      const tag = Tag(id: 't1', name: '   ');
      expect(() => repo.insert(tag), throwsArgumentError);
    });

    test('insert throws StateError on duplicate id', () async {
      const tag = Tag(id: 't1', name: 'first');
      await repo.insert(tag);

      const dup = Tag(id: 't1', name: 'second');
      expect(() => repo.insert(dup), throwsStateError);
    });

    test('insert throws on duplicate name (UNIQUE constraint)', () async {
      const t1 = Tag(id: 't1', name: 'UniqueTag');
      const t2 = Tag(id: 't2', name: 'UniqueTag');
      await repo.insert(t1);
      expect(() => repo.insert(t2), throwsA(anything));
    });

    // -------------------------------------------------------------------------
    // update
    // -------------------------------------------------------------------------

    test('update renames an existing tag', () async {
      const original = Tag(id: 't1', name: 'OldName');
      await repo.insert(original);

      const renamed = Tag(id: 't1', name: 'NewName');
      await repo.update(renamed);

      final all = await repo.findAll();
      expect(all.first.name, 'NewName');
    });

    test('update trims whitespace from new name', () async {
      const tag = Tag(id: 't1', name: 'Before');
      await repo.insert(tag);

      const updated = Tag(id: 't1', name: '  After  ');
      await repo.update(updated);

      final all = await repo.findAll();
      expect(all.first.name, 'After');
    });

    test('update throws StateError when tag id does not exist', () async {
      const ghost = Tag(id: 'nonexistent', name: 'Ghost');
      expect(() => repo.update(ghost), throwsStateError);
    });

    test('update throws ArgumentError on blank new name', () async {
      const tag = Tag(id: 't1', name: 'Valid');
      await repo.insert(tag);

      const blank = Tag(id: 't1', name: '');
      expect(() => repo.update(blank), throwsArgumentError);
    });

    test('update throws on name collision with another tag', () async {
      const t1 = Tag(id: 't1', name: 'Alpha');
      const t2 = Tag(id: 't2', name: 'Beta');
      await repo.insert(t1);
      await repo.insert(t2);

      const collision = Tag(id: 't1', name: 'Beta');
      expect(() => repo.update(collision), throwsA(anything));
    });

    // -------------------------------------------------------------------------
    // delete cascade (business_card_tags)
    // -------------------------------------------------------------------------

    test('delete cascades to business_card_tags', () async {
      // Verify the ON DELETE CASCADE FK is active by checking that deleting a
      // tag removes its join rows.  We insert directly via the raw DB to avoid
      // pulling in CardRepository as a dependency of this test file.
      final tag = await repo.findOrCreate('cascadeTag');

      // Insert a stub card and a join row manually.
      await db.execute(
        "INSERT INTO business_cards(id, image_path, created_at) VALUES (?, ?, ?)",
        ['card-stub', '/img/stub.jpg', '2026-01-01T00:00:00.000Z'],
      );
      await db.execute(
        'INSERT INTO business_card_tags(card_id, tag_id) VALUES (?, ?)',
        ['card-stub', tag.id],
      );

      // Verify the join row exists.
      final before = await db.query(
        'business_card_tags',
        where: 'tag_id = ?',
        whereArgs: [tag.id],
      );
      expect(before.length, 1);

      await repo.delete(tag.id);

      final after = await db.query(
        'business_card_tags',
        where: 'tag_id = ?',
        whereArgs: [tag.id],
      );
      expect(after, isEmpty);
    });
  });
}
