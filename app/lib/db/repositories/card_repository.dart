import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/business_card.dart';
import '../../models/event.dart';
import '../../models/tag.dart';

/// Abstract interface for business-card persistence.
abstract interface class CardRepository {
  Future<BusinessCard?> findById(String id);

  /// Returns all cards, excluding the my-card by default.
  ///
  /// Pass [includeMyCard: true] to include the card flagged as my-card.
  Future<List<BusinessCard>> findAll({
    int? limit,
    int? offset,
    CardSortBy sortBy,
    bool includeMyCard,
  });

  /// Returns cards associated with [tagId], excluding my-card.
  Future<List<BusinessCard>> findByTag(String tagId);

  /// Returns cards associated with [eventId], excluding my-card.
  Future<List<BusinessCard>> findByEvent(String eventId);

  Future<void> insert(BusinessCard card);
  Future<void> update(BusinessCard card);
  Future<void> delete(String id);

  /// Returns the single card flagged as my-card, or null if none is set.
  Future<BusinessCard?> findMyCard();

  /// Designates [cardId] as the my-card.
  ///
  /// Clears any existing my-card flag in the same transaction, ensuring at most
  /// one card ever has is_my_card = 1.
  Future<void> setMyCard(String cardId);

  /// Clears the my-card flag from whichever card currently holds it, if any.
  Future<void> clearMyCard();
}

/// SQLite-backed implementation of [CardRepository].
///
/// Tags and events are eagerly loaded for every returned card via a single
/// aggregated query (GROUP_CONCAT) so callers never see a leaky cursor.
///
/// Event association uses the [business_card_events] junction table introduced
/// in migration0002.  The legacy [business_cards.event_id] column is read only
/// for [CardSortBy.event] ordering (it still holds a nullable single event_id
/// for backward-compat); writes no longer touch that column.
class SqliteCardRepository implements CardRepository {
  const SqliteCardRepository(this._db);

  final Database _db;

  // --------------------------------------------------------------------------
  // Shared SELECT projection
  // --------------------------------------------------------------------------

  /// Columns selected in every card query.
  ///
  /// Tags and events are loaded via correlated subqueries to avoid the
  /// Cartesian product that would arise from joining both junction tables in
  /// the same query, and to avoid the need for GROUP_CONCAT(DISTINCT …, sep)
  /// which requires SQLite ≥ 3.44 (not guaranteed by sqflite_common_ffi).
  ///
  /// Separator conventions:
  ///   tags:   entry separator `||`  field separator `|`
  ///           → "id1|name1||id2|name2"
  ///   events: entry separator CHAR(30) = '\x1e'  field separator CHAR(31) = '\x1f'
  ///           → "id1\x1fname1\x1fdate1\x1fmemo1\x1eid2\x1fname2\x1f..."
  static const _selectColumns = '''
    bc.id,
    bc.image_path,
    bc.back_image_path,
    bc.display_name,
    bc.sns_links_json,
    bc.memo,
    bc.created_at,
    bc.is_my_card,
    (SELECT GROUP_CONCAT(t.id || '|' || t.name, '||')
     FROM business_card_tags bct2
     JOIN tags t ON t.id = bct2.tag_id
     WHERE bct2.card_id = bc.id) AS tag_pairs,
    (SELECT GROUP_CONCAT(e.id || CHAR(31) || e.name || CHAR(31) || COALESCE(e.date, '') || CHAR(31) || COALESCE(e.memo, ''), CHAR(30))
     FROM business_card_events bce2
     JOIN events e ON e.id = bce2.event_id
     WHERE bce2.card_id = bc.id) AS event_pairs
  ''';

  // No joins needed in the base query — aggregates use correlated subqueries.
  static const _baseJoins = '';

  // --------------------------------------------------------------------------
  // Public interface
  // --------------------------------------------------------------------------

  @override
  Future<BusinessCard?> findById(String id) async {
    final sql = '''
      SELECT $_selectColumns
      FROM business_cards bc
      $_baseJoins
      WHERE bc.id = ?
      GROUP BY bc.id
    ''';
    final rows = await _db.rawQuery(sql, [id]);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<List<BusinessCard>> findAll({
    int? limit,
    int? offset,
    CardSortBy sortBy = CardSortBy.createdAt,
    bool includeMyCard = false,
  }) async {
    final orderClause = _orderClause(sortBy);
    final myCardFilter = includeMyCard ? '' : 'WHERE bc.is_my_card = 0';
    final sql = '''
      SELECT $_selectColumns
      FROM business_cards bc
      $_baseJoins
      $myCardFilter
      GROUP BY bc.id
      ORDER BY $orderClause
      ${limit != null ? 'LIMIT ?' : ''}
      ${offset != null ? 'OFFSET ?' : ''}
    ''';

    final args = <Object?>[];
    if (limit != null) args.add(limit);
    if (offset != null) args.add(offset);

    final rows = await _db.rawQuery(sql, args.isEmpty ? null : args);
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<List<BusinessCard>> findByTag(String tagId) async {
    final sql = '''
      SELECT $_selectColumns
      FROM business_cards bc
      INNER JOIN business_card_tags bct_filter
        ON bct_filter.card_id = bc.id AND bct_filter.tag_id = ?
      $_baseJoins
      WHERE bc.is_my_card = 0
      GROUP BY bc.id
      ORDER BY bc.created_at DESC
    ''';
    final rows = await _db.rawQuery(sql, [tagId]);
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<List<BusinessCard>> findByEvent(String eventId) async {
    final sql = '''
      SELECT $_selectColumns
      FROM business_cards bc
      INNER JOIN business_card_events bce_filter
        ON bce_filter.card_id = bc.id AND bce_filter.event_id = ?
      $_baseJoins
      WHERE bc.is_my_card = 0
      GROUP BY bc.id
      ORDER BY bc.created_at DESC
    ''';
    final rows = await _db.rawQuery(sql, [eventId]);
    return List.unmodifiable(rows.map(_fromRow));
  }

  @override
  Future<void> insert(BusinessCard card) async {
    // FTS note: the AFTER INSERT trigger on business_cards fires immediately
    // after the card row lands, before any junction rows exist — so
    // event_name is temporarily empty.  Each subsequent business_card_events
    // insert fires trg_bce_fts_insert, which rebuilds the FTS row with the
    // current event set.  Final FTS state after commit is complete because
    // SQLite hides intermediate state from concurrent readers (WAL / journal).
    await _db.transaction((txn) async {
      await txn.insert(
        'business_cards',
        _cardToRow(card),
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
      await _insertTagLinks(txn, card.id, card.tags);
      await _insertEventLinks(txn, card.id, card.events);
    });
  }

  @override
  Future<void> update(BusinessCard card) async {
    await _db.transaction((txn) async {
      await txn.update(
        'business_cards',
        _cardToRow(card),
        where: 'id = ?',
        whereArgs: [card.id],
        conflictAlgorithm: ConflictAlgorithm.fail,
      );
      // Replace all tag links atomically.
      await txn.delete(
        'business_card_tags',
        where: 'card_id = ?',
        whereArgs: [card.id],
      );
      await _insertTagLinks(txn, card.id, card.tags);
      // Replace all event links atomically.
      await txn.delete(
        'business_card_events',
        where: 'card_id = ?',
        whereArgs: [card.id],
      );
      await _insertEventLinks(txn, card.id, card.events);
    });
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      // business_card_tags and business_card_events CASCADE delete via FK;
      // FTS trigger fires on DELETE of business_cards.
      await txn.delete('business_cards', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<BusinessCard?> findMyCard() async {
    final sql = '''
      SELECT $_selectColumns
      FROM business_cards bc
      $_baseJoins
      WHERE bc.is_my_card = 1
      GROUP BY bc.id
      LIMIT 1
    ''';
    final rows = await _db.rawQuery(sql);
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  @override
  Future<void> setMyCard(String cardId) async {
    await _db.transaction((txn) async {
      // Clear any existing my-card flag first (mutual exclusion).
      await txn.rawUpdate(
        'UPDATE business_cards SET is_my_card = 0 WHERE is_my_card = 1',
      );
      // Set the flag on the target card.
      await txn.rawUpdate(
        'UPDATE business_cards SET is_my_card = 1 WHERE id = ?',
        [cardId],
      );
    });
  }

  @override
  Future<void> clearMyCard() async {
    await _db.rawUpdate(
      'UPDATE business_cards SET is_my_card = 0 WHERE is_my_card = 1',
    );
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  static Future<void> _insertTagLinks(
    Transaction txn,
    String cardId,
    List<Tag> tags,
  ) async {
    for (final tag in tags) {
      await txn.insert(
        'business_card_tags',
        {'card_id': cardId, 'tag_id': tag.id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static Future<void> _insertEventLinks(
    Transaction txn,
    String cardId,
    List<Event> events,
  ) async {
    for (final event in events) {
      await txn.insert(
        'business_card_events',
        {'card_id': cardId, 'event_id': event.id},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  static String _orderClause(CardSortBy sortBy) {
    switch (sortBy) {
      case CardSortBy.createdAt:
        return 'bc.created_at DESC';
      case CardSortBy.name:
        return 'bc.display_name ASC NULLS LAST';
      case CardSortBy.event:
        // Order by the minimum event_id from the junction table, falling back
        // to created_at for cards with no events.
        return '(SELECT MIN(bce_ord.event_id) FROM business_card_events bce_ord WHERE bce_ord.card_id = bc.id) ASC NULLS LAST, bc.created_at DESC';
    }
  }

  /// Maps a card to its storable columns.
  /// Does NOT include event_id — that legacy column is deprecated and no
  /// longer written.  It remains in the schema for backward-compat only.
  static Map<String, Object?> _cardToRow(BusinessCard card) {
    return {
      'id': card.id,
      'image_path': card.imagePath,
      'back_image_path': card.backImagePath,
      'display_name': card.displayName,
      'sns_links_json': jsonEncode(card.snsLinks),
      'memo': card.memo,
      'created_at': card.createdAt.toIso8601String(),
      'is_my_card': card.isMyCard ? 1 : 0,
    };
  }

  static BusinessCard _fromRow(Map<String, Object?> row) {
    final tagPairsRaw = row['tag_pairs'] as String?;
    final tags = _parseTags(tagPairsRaw);

    final eventPairsRaw = row['event_pairs'] as String?;
    final events = _parseEvents(eventPairsRaw);

    final snsRaw = row['sns_links_json'] as String?;
    final snsLinks = snsRaw != null
        ? List<String>.unmodifiable(
            (jsonDecode(snsRaw) as List<dynamic>).cast<String>(),
          )
        : const <String>[];

    return BusinessCard(
      id: row['id'] as String,
      imagePath: row['image_path'] as String,
      backImagePath: row['back_image_path'] as String?,
      displayName: row['display_name'] as String?,
      snsLinks: snsLinks,
      memo: row['memo'] as String?,
      events: events,
      createdAt: DateTime.parse(row['created_at'] as String),
      tags: tags,
      isMyCard: (row['is_my_card'] as int?) == 1,
    );
  }

  /// Parses `"id1|name1||id2|name2"` produced by GROUP_CONCAT.
  static List<Tag> _parseTags(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final pairs = raw.split('||');
    final tags = <Tag>[];
    for (final pair in pairs) {
      final sep = pair.indexOf('|');
      if (sep < 0) continue;
      final id = pair.substring(0, sep);
      final name = pair.substring(sep + 1);
      tags.add(Tag(id: id, name: name));
    }
    return List.unmodifiable(tags);
  }

  /// Parses the event_pairs aggregate produced by GROUP_CONCAT.
  /// Entry separator: CHAR(30) = '\x1e'
  /// Field separator: CHAR(31) = '\x1f'
  /// Format: "id1\x1fname1\x1fdate1\x1fmemo1\x1eid2\x1fname2\x1f..."
  static List<Event> _parseEvents(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final entries = raw.split('\x1e');
    final events = <Event>[];
    for (final entry in entries) {
      final parts = entry.split('\x1f');
      if (parts.length < 2) continue;
      final id = parts[0];
      final name = parts[1];
      final dateStr = parts.length > 2 ? parts[2] : '';
      final memo = parts.length > 3 ? parts[3] : '';
      events.add(Event(
        id: id,
        name: name,
        date: dateStr.isNotEmpty ? DateTime.tryParse(dateStr) : null,
        memo: memo.isNotEmpty ? memo : null,
      ));
    }
    return List.unmodifiable(events);
  }
}
