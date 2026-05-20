import 'event.dart';
import 'tag.dart';

/// Sort options for business card list queries.
enum CardSortBy { createdAt, name, event }

/// Immutable domain model for a scanned business / fan card.
class BusinessCard {
  const BusinessCard({
    required this.id,
    required this.imagePath,
    this.backImagePath,
    this.displayName,
    required this.snsLinks,
    this.memo,
    required this.events,
    required this.createdAt,
    required this.tags,
    this.isMyCard = false,
  });

  final String id;
  final String imagePath;

  /// Optional file-system path to the back-side card image.
  final String? backImagePath;

  final String? displayName;

  /// Unmodifiable list of SNS link strings (URLs / IDs).
  final List<String> snsLinks;

  final String? memo;

  /// Eagerly loaded events this card is associated with. Unmodifiable.
  final List<Event> events;

  final DateTime createdAt;

  /// Eagerly loaded tags. Unmodifiable.
  final List<Tag> tags;

  /// Whether this card is the user's own profile card ("マイカード").
  /// At most one card in the database has this set to true.
  final bool isMyCard;

  /// Returns a copy of this card with the given fields replaced.
  ///
  /// For non-nullable fields the standard `?? this.field` pattern applies.
  ///
  /// For nullable fields ([backImagePath], [displayName], [memo]) the same
  /// pattern is used: passing `null` leaves the existing value unchanged.
  /// To explicitly clear a nullable field to null, construct a new
  /// [BusinessCard] directly (as [UpdateCardUseCase] does), which avoids the
  /// ambiguity inherent in the `??` sentinel approach.
  BusinessCard copyWith({
    String? id,
    String? imagePath,
    String? backImagePath,
    String? displayName,
    List<String>? snsLinks,
    String? memo,
    List<Event>? events,
    DateTime? createdAt,
    List<Tag>? tags,
    bool? isMyCard,
  }) {
    return BusinessCard(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      backImagePath: backImagePath ?? this.backImagePath,
      displayName: displayName ?? this.displayName,
      snsLinks: snsLinks != null ? List.unmodifiable(snsLinks) : this.snsLinks,
      memo: memo ?? this.memo,
      events: events != null ? List.unmodifiable(events) : this.events,
      createdAt: createdAt ?? this.createdAt,
      tags: tags != null ? List.unmodifiable(tags) : this.tags,
      isMyCard: isMyCard ?? this.isMyCard,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessCard &&
          other.id == id &&
          other.imagePath == imagePath &&
          other.backImagePath == backImagePath &&
          other.displayName == displayName &&
          other.memo == memo &&
          other.createdAt == createdAt &&
          other.isMyCard == isMyCard;

  @override
  int get hashCode => Object.hash(
        id,
        imagePath,
        backImagePath,
        displayName,
        memo,
        createdAt,
        isMyCard,
      );

  @override
  String toString() =>
      'BusinessCard(id: $id, displayName: $displayName, backImagePath: $backImagePath, isMyCard: $isMyCard, events: ${events.map((e) => e.id).toList()}, createdAt: $createdAt)';
}
