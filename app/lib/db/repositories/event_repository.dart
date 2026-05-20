import 'package:sqflite/sqflite.dart';

import '../../models/event.dart';

/// Abstract interface for event persistence.
abstract interface class EventRepository {
  Future<List<Event>> findAll({bool orderByDateDesc = true});
  Future<Event?> findById(String id);

  /// Returns all events whose [Event.date] falls within [[from], [to]]
  /// inclusive (ISO8601 string comparison).  Events with a null date are
  /// excluded.  Results are ordered by date ascending.
  Future<List<Event>> findByDateRange(DateTime from, DateTime to);

  Future<void> insert(Event event);
  Future<void> update(Event event);
  Future<void> delete(String id);
}

/// SQLite-backed implementation of [EventRepository].
class SqliteEventRepository implements EventRepository {
  const SqliteEventRepository(this._db);

  final Database _db;

  static const _table = 'events';

  @override
  Future<List<Event>> findAll({bool orderByDateDesc = true}) async {
    final orderClause = orderByDateDesc ? 'date DESC NULLS LAST' : 'date ASC NULLS LAST';
    final rows = await _db.query(
      _table,
      columns: ['id', 'name', 'date', 'memo'],
      orderBy: orderClause,
    );
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<Event?> findById(String id) async {
    final rows = await _db.query(
      _table,
      columns: ['id', 'name', 'date', 'memo'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> insert(Event event) async {
    await _db.transaction((txn) async {
      await txn.insert(
        _table,
        _toRow(event),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
    });
  }

  @override
  Future<void> update(Event event) async {
    await _db.transaction((txn) async {
      await txn.update(
        _table,
        _toRow(event),
        where: 'id = ?',
        whereArgs: [event.id],
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
    });
  }

  @override
  Future<List<Event>> findByDateRange(DateTime from, DateTime to) async {
    // ISO8601 strings sort lexicographically, so string BETWEEN works correctly
    // for full-date and date-time values stored in the same format.
    final rows = await _db.query(
      _table,
      columns: ['id', 'name', 'date', 'memo'],
      where: 'date IS NOT NULL AND date >= ? AND date <= ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'date ASC',
    );
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      await txn.delete(_table, where: 'id = ?', whereArgs: [id]);
    });
  }

  // --------------------------------------------------------------------------

  static Event _fromRow(Map<String, Object?> row) {
    return Event(
      id: row['id'] as String,
      name: row['name'] as String,
      date: row['date'] != null
          ? DateTime.parse(row['date'] as String)
          : null,
      memo: row['memo'] as String?,
    );
  }

  static Map<String, Object?> _toRow(Event e) {
    return {
      'id': e.id,
      'name': e.name,
      'date': e.date?.toIso8601String(),
      'memo': e.memo,
    };
  }
}
