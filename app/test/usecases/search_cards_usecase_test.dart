import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otameishi/db/repositories/search_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/usecases/search_cards_usecase.dart';

class _MockSearch extends Mock implements SearchRepository {}

BusinessCard _card({
  required String id,
  List<Tag> tags = const [],
}) =>
    BusinessCard(
      id: id,
      imagePath: '/p',
      snsLinks: const [],
      events: const [],
      tags: List.unmodifiable(tags),
      createdAt: DateTime.utc(2026),
    );

void main() {
  late _MockSearch repo;
  late SearchCardsUseCase useCase;

  setUp(() {
    repo = _MockSearch();
    useCase = SearchCardsUseCase(repo);
  });

  test('returns repo results when no filters', () async {
    final cards = [_card(id: '1'), _card(id: '2')];
    when(
      () => repo.search('q', eventIds: null, tagIds: null),
    ).thenAnswer((_) async => cards);

    final result = await useCase.execute('q');
    expect(result.map((c) => c.id), ['1', '2']);
  });

  test('passes tagIds filter through to repo', () async {
    final t = const Tag(id: 'oshi', name: 'oshi');
    final expected = [_card(id: '1', tags: [t])];
    when(
      () => repo.search('q', eventIds: null, tagIds: {'oshi'}),
    ).thenAnswer((_) async => expected);

    final result = await useCase.execute(
      'q',
      filters: const SearchFilters(tagIds: {'oshi'}),
    );
    expect(result.map((c) => c.id), ['1']);
  });

  test('passes eventIds filter through to repo', () async {
    final expected = [_card(id: '1')];
    when(
      () => repo.search('q', eventIds: {'e1'}, tagIds: null),
    ).thenAnswer((_) async => expected);

    final result = await useCase.execute(
      'q',
      filters: const SearchFilters(eventIds: {'e1'}),
    );
    expect(result.map((c) => c.id), ['1']);
  });

  test('passes both eventIds and tagIds through to repo', () async {
    final t = const Tag(id: 'oshi', name: 'oshi');
    final expected = [_card(id: '1', tags: [t])];
    when(
      () => repo.search('q', eventIds: {'e1'}, tagIds: {'oshi'}),
    ).thenAnswer((_) async => expected);

    final result = await useCase.execute(
      'q',
      filters: const SearchFilters(eventIds: {'e1'}, tagIds: {'oshi'}),
    );
    expect(result.map((c) => c.id), ['1']);
  });

  test('filter-only (empty query) passes through to repo', () async {
    final expected = [_card(id: '1')];
    when(
      () => repo.search('', eventIds: {'e1'}, tagIds: null),
    ).thenAnswer((_) async => expected);

    final result = await useCase.execute(
      '',
      filters: const SearchFilters(eventIds: {'e1'}),
    );
    expect(result.map((c) => c.id), ['1']);
  });

  test('empty query with empty filters passes through (repo returns empty)',
      () async {
    when(
      () => repo.search('', eventIds: null, tagIds: null),
    ).thenAnswer((_) async => []);

    final result = await useCase.execute('');
    expect(result, isEmpty);
  });
}
