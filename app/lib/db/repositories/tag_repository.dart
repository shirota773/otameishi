import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../models/tag.dart';

/// A [Tag] paired with how many business cards reference it.
class TagWithCount {
  const TagWithCount({required this.tag, required this.cardCount});

  final Tag tag;
  final int cardCount;
}

/// Abstract interface for tag persistence.
abstract interface class TagRepository {
  Future<List<Tag>> findAll();

  /// Returns every tag sorted by name, each paired with the number of
  /// business cards that reference it.
  Future<List<TagWithCount>> findAllWithCounts();

  /// Returns the existing [Tag] whose name matches [name] case-insensitively,
  /// or creates and returns a new one.  Idempotent.
  Future<Tag> findOrCreate(String name);

  /// Persists a new [tag] whose [Tag.id] and [Tag.name] are already set by
  /// the caller.  Throws [StateError] if a tag with the same id already
  /// exists, or a database error if the name violates the UNIQUE constraint.
  Future<void> insert(Tag tag);

  /// Renames an existing tag identified by [tag.id] to [tag.name].
  /// Throws [StateError] if no tag with that id exists.
  /// Throws a database error if [tag.name] collides with another tag name.
  Future<void> update(Tag tag);

  Future<void> delete(String id);
}

/// SQLite-backed implementation of [TagRepository].
class SqliteTagRepository implements TagRepository {
  SqliteTagRepository(this._db);

  final Database _db;

  static const _table = 'tags';
  static const _uuid = Uuid();

  @override
  Future<List<Tag>> findAll() async {
    final rows = await _db.query(
      _table,
      columns: ['id', 'name'],
      orderBy: 'name ASC',
    );
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<List<TagWithCount>> findAllWithCounts() async {
    final rows = await _db.rawQuery('''
      SELECT t.id, t.name, COUNT(bct.card_id) AS card_count
      FROM tags t
      LEFT JOIN business_card_tags bct ON bct.tag_id = t.id
      GROUP BY t.id, t.name
      ORDER BY t.name ASC
    ''');
    return List.unmodifiable(
      rows.map(
        (r) => TagWithCount(
          tag: Tag(id: r['id'] as String, name: r['name'] as String),
          cardCount: r['card_count'] as int,
        ),
      ),
    );
  }

  @override
  Future<Tag> findOrCreate(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Tag name must not be blank');
    }

    return _db.transaction((txn) async {
      // Case-insensitive lookup (COLLATE NOCASE on column covers this).
      final rows = await txn.query(
        _table,
        columns: ['id', 'name'],
        where: 'name = ?',
        whereArgs: [trimmed],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return _fromRow(rows.first);
      }
      final newTag = Tag(id: _uuid.v4(), name: trimmed);
      await txn.insert(_table, {'id': newTag.id, 'name': newTag.name});
      return newTag;
    });
  }

  @override
  Future<void> insert(Tag tag) async {
    final trimmed = tag.name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(tag.name, 'tag.name', 'Tag name must not be blank');
    }
    await _db.transaction((txn) async {
      final count = Sqflite.firstIntValue(
        await txn.query(_table, columns: ['COUNT(*)'], where: 'id = ?', whereArgs: [tag.id]),
      )!;
      if (count > 0) {
        throw StateError('Tag with id ${tag.id} already exists');
      }
      await txn.insert(_table, {'id': tag.id, 'name': trimmed});
    });
  }

  @override
  Future<void> update(Tag tag) async {
    final trimmed = tag.name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(tag.name, 'tag.name', 'Tag name must not be blank');
    }
    await _db.transaction((txn) async {
      final affected = await txn.update(
        _table,
        {'name': trimmed},
        where: 'id = ?',
        whereArgs: [tag.id],
      );
      if (affected == 0) {
        throw StateError('No tag found with id ${tag.id}');
      }
    });
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  // --------------------------------------------------------------------------

  static Tag _fromRow(Map<String, Object?> row) {
    return Tag(id: row['id'] as String, name: row['name'] as String);
  }
}
