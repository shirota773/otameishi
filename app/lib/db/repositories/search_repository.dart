import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../models/business_card.dart';
import '../../models/event.dart';
import '../../models/tag.dart';

/// Abstract interface for full-text search over business cards.
abstract interface class SearchRepository {
  /// Searches [cards_fts] for [query] and returns matching cards ranked by
  /// FTS5 relevance (best match first).
  ///
  /// When [query] is blank/whitespace-only but [eventIds] or [tagIds] are
  /// non-empty, returns all cards matching those filters (no FTS requirement).
  ///
  /// Returns an empty list only when query is blank AND both filter sets are
  /// empty.
  ///
  /// All [?] placeholders are parameterized — no user input is concatenated
  /// into SQL strings.
  Future<List<BusinessCard>> search(
    String query, {
    Set<String>? eventIds,
    Set<String>? tagIds,
  });
}

/// SQLite FTS5-backed implementation of [SearchRepository].
///
/// The FTS5 table [cards_fts] is kept in sync by triggers defined in the
/// initial migration and migration0002.  Each row contains a denormalised
/// snapshot of: display_name, memo, event_name (all linked events), tag_names.
///
/// Query strategy
/// --------------
/// User input is split into whitespace-separated tokens.  Each token is
/// wrapped in double-quotes (FTS5 phrase literal) and suffixed with `*`
/// (prefix match).  Tokens are joined with implicit AND so all must match.
///
///   "test"* AND "ユーザー"*
///
/// This means:
///   - `test` matches `testuser`, `testmemo`, etc.  (prefix)
///   - Special FTS5 operators in user input (AND, OR, NOT, NEAR, ^) are
///     neutralised because each token is wrapped in double-quotes.
///   - Double-quote characters inside a token are escaped as `""`.
///   - Multi-word phrases from the user become multi-token prefix-AND queries,
///     which is the most useful UX for a search box.
///
/// CJK note: under unicode61 tokenizer, each CJK character is its own token.
/// A single kanji/kana query therefore does exact-token matching rather than
/// prefix matching (the `*` has no additional effect for single-character
/// tokens).  This is adequate for typical Japanese name / event searches.
class SqliteSearchRepository implements SearchRepository {
  const SqliteSearchRepository(this._db);

  final Database _db;

  @override
  Future<List<BusinessCard>> search(
    String query, {
    Set<String>? eventIds,
    Set<String>? tagIds,
  }) async {
    final trimmed = query.trim();
    final hasQuery = trimmed.isNotEmpty;
    final hasEventFilter = eventIds != null && eventIds.isNotEmpty;
    final hasTagFilter = tagIds != null && tagIds.isNotEmpty;

    if (!hasQuery && !hasEventFilter && !hasTagFilter) return const [];

    final args = <Object?>[];
    final whereClauses = <String>[];

    // Always exclude the my-card from search results.
    whereClauses.add('bc.is_my_card = 0');

    // FTS match — only when a query is provided.
    final String fromClause;
    if (hasQuery) {
      fromClause = '''
        FROM cards_fts
        JOIN business_cards bc ON bc.id = cards_fts.card_id
      ''';
      whereClauses.add('cards_fts MATCH ?');
      args.add(_buildFtsQuery(trimmed));
    } else {
      fromClause = 'FROM business_cards bc';
    }

    // Event filter — uses the junction table introduced in migration0002.
    final String eventJoin;
    if (hasEventFilter) {
      eventJoin =
          'JOIN business_card_events bce_f ON bce_f.card_id = bc.id';
      final placeholders = List.filled(eventIds.length, '?').join(', ');
      whereClauses.add('bce_f.event_id IN ($placeholders)');
      args.addAll(eventIds);
    } else {
      eventJoin = '';
    }

    // Tag filter — requires a JOIN; we GROUP BY to deduplicate.
    final String tagJoin;
    if (hasTagFilter) {
      tagJoin = 'JOIN business_card_tags bct_f ON bct_f.card_id = bc.id';
      final placeholders = List.filled(tagIds.length, '?').join(', ');
      whereClauses.add('bct_f.tag_id IN ($placeholders)');
      args.addAll(tagIds);
    } else {
      tagJoin = '';
    }

    final whereClause = whereClauses.isEmpty
        ? ''
        : 'WHERE ${whereClauses.join(' AND ')}';

    // rank is only available when selecting from cards_fts.
    final rankSelect = hasQuery ? ', rank' : '';
    final orderBy = hasQuery ? 'ORDER BY rank' : 'ORDER BY bc.created_at DESC';

    final sql = '''
      SELECT
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
        $rankSelect
      $fromClause
      $eventJoin
      $tagJoin
      $whereClause
      GROUP BY bc.id
      $orderBy
    ''';

    final rows = await _db.rawQuery(sql, args);
    return List.unmodifiable(rows.map(_fromRow));
  }

  // --------------------------------------------------------------------------

  /// Converts user-typed [query] to a safe FTS5 MATCH expression.
  ///
  /// Each whitespace-separated token becomes `"<escaped>"*` so:
  ///   - FTS5 special chars are inert (wrapped in quotes)
  ///   - Prefix matching applies (trailing `*` outside the quotes)
  static String _buildFtsQuery(String query) {
    final tokens = query.split(RegExp(r'\s+'));
    final parts = tokens
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*');
    return parts.join(' ');
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
