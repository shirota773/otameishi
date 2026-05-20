import '../db/repositories/search_repository.dart';
import '../models/business_card.dart';

/// Multi-value filters that narrow search results at the SQL layer.
///
/// Both sets use inclusive OR within each dimension and AND across dimensions:
///   eventIds: {e1, e2} → card.event_id IN (e1, e2)
///   tagIds:   {t1, t2} → card has at least one tag IN (t1, t2)
///   combined: both conditions must hold simultaneously.
class SearchFilters {
  const SearchFilters({
    this.eventIds = const {},
    this.tagIds = const {},
  });

  final Set<String> eventIds;
  final Set<String> tagIds;

  bool get isEmpty => eventIds.isEmpty && tagIds.isEmpty;

  SearchFilters copyWith({
    Set<String>? eventIds,
    Set<String>? tagIds,
  }) {
    return SearchFilters(
      eventIds: eventIds ?? this.eventIds,
      tagIds: tagIds ?? this.tagIds,
    );
  }
}

class SearchCardsUseCase {
  const SearchCardsUseCase(this._repo);

  final SearchRepository _repo;

  Future<List<BusinessCard>> execute(
    String query, {
    SearchFilters filters = const SearchFilters(),
  }) {
    return _repo.search(
      query,
      eventIds: filters.eventIds.isEmpty ? null : filters.eventIds,
      tagIds: filters.tagIds.isEmpty ? null : filters.tagIds,
    );
  }
}
