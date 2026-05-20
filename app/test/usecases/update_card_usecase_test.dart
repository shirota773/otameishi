import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'dart:typed_data';

import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/services/storage_service.dart';
import 'package:otameishi/usecases/update_card_usecase.dart';

class _MockCardRepo extends Mock implements CardRepository {}

class _MockTagRepo extends Mock implements TagRepository {}

class _MockEventRepo extends Mock implements EventRepository {}

class _FakeStorage implements StorageService {
  final List<String> deleted = [];

  @override
  Future<String> saveCardImage(
    Uint8List bytes, {
    required ImageFormat format,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> deleteCardImage(String path) async {
    deleted.add(path);
  }

  @override
  Future<int> cleanupOrphans(Set<String> validPaths) async => 0;
}

Tag _tag(String id, String name) => Tag(id: id, name: name);

Event _event(String id, String name) => Event(id: id, name: name);

BusinessCard _existingCard({
  String id = 'card-1',
  String imagePath = '/photos/card.jpg',
  String? displayName = '山田太郎',
  String? memo,
  List<Tag> tags = const [],
  List<Event> events = const [],
}) =>
    BusinessCard(
      id: id,
      imagePath: imagePath,
      displayName: displayName,
      snsLinks: const ['@yamada', 'https://example.com'],
      memo: memo,
      events: List.unmodifiable(events),
      createdAt: DateTime.utc(2025, 8, 1),
      tags: List.unmodifiable(tags),
    );

void main() {
  late _MockCardRepo cardRepo;
  late _MockTagRepo tagRepo;
  late _MockEventRepo eventRepo;
  late _FakeStorage storage;
  late UpdateCardUseCase useCase;

  setUpAll(() {
    registerFallbackValue(_existingCard());
    registerFallbackValue(_tag('x', 'x'));
    registerFallbackValue(_event('x', 'x'));
  });

  setUp(() {
    cardRepo = _MockCardRepo();
    tagRepo = _MockTagRepo();
    eventRepo = _MockEventRepo();
    storage = _FakeStorage();
    useCase = UpdateCardUseCase(
      cardRepository: cardRepo,
      tagRepository: tagRepo,
      eventRepository: eventRepo,
      storage: storage,
    );
    when(() => cardRepo.findById('card-1'))
        .thenAnswer((_) async => _existingCard());
    when(() => cardRepo.update(any())).thenAnswer((_) async {});
  });

  test('updates displayName and preserves imagePath and createdAt', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: '新しい名前',
      memo: null,
      eventIds: const [],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.displayName, '新しい名前');
    expect(result.imagePath, '/photos/card.jpg');
    expect(result.createdAt, DateTime.utc(2025, 8, 1));
    verify(() => cardRepo.update(any())).called(1);
  });

  test('preserves the original card ID', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: '名前',
      memo: null,
      eventIds: const [],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.id, 'card-1');
  });

  test('resolves tag names via findOrCreate and attaches to updated card', () async {
    when(() => tagRepo.findOrCreate('コミケ'))
        .thenAnswer((_) async => _tag('t1', 'コミケ'));
    when(() => tagRepo.findOrCreate('vtuber'))
        .thenAnswer((_) async => _tag('t2', 'vtuber'));

    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: null,
      eventIds: const [],
      tagNames: const ['コミケ', '  ', '', 'vtuber'],
      xHandles: const [],
      urls: const [],
    ));

    verify(() => tagRepo.findOrCreate('コミケ')).called(1);
    verify(() => tagRepo.findOrCreate('vtuber')).called(1);
    verifyNever(() => tagRepo.findOrCreate(''));
    expect(result.tags.map((t) => t.name), containsAll(['コミケ', 'vtuber']));
  });

  test('resolves event ids and attaches to updated card', () async {
    when(() => eventRepo.findById('evt-1'))
        .thenAnswer((_) async => _event('evt-1', 'Comiket'));
    when(() => eventRepo.findById('evt-2'))
        .thenAnswer((_) async => _event('evt-2', 'にじフェス'));

    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: null,
      eventIds: const ['evt-1', 'evt-2'],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.events.length, 2);
    expect(result.events.map((e) => e.id).toSet(), {'evt-1', 'evt-2'});
  });

  test('unknown event id is silently skipped', () async {
    when(() => eventRepo.findById('ghost')).thenAnswer((_) async => null);

    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: null,
      eventIds: const ['ghost'],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.events, isEmpty);
  });

  test('builds snsLinks from xHandles and urls', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: null,
      eventIds: const [],
      tagNames: const [],
      xHandles: const ['@alice', '@bob'],
      urls: const ['https://alice.com'],
    ));

    expect(result.snsLinks, ['@alice', '@bob', 'https://alice.com']);
  });

  test('empty xHandles and urls results in empty snsLinks', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: null,
      eventIds: const [],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.snsLinks, isEmpty);
  });

  test('memo is updated on the card', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: null,
      memo: '推しの子大好き',
      eventIds: const [],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    expect(result.memo, '推しの子大好き');
  });

  test('throws StateError when card is not found', () async {
    when(() => cardRepo.findById('missing'))
        .thenAnswer((_) async => null);

    expect(
      () => useCase.execute(UpdateCardInput(
        cardId: 'missing',
        displayName: null,
        memo: null,
        eventIds: const [],
        tagNames: const [],
        xHandles: const [],
        urls: const [],
      )),
      throwsA(isA<StateError>()),
    );
  });

  test('backImagePath is set when provided', () async {
    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      backImagePath: '/photos/card_back.jpg',
    ));
    expect(result.backImagePath, '/photos/card_back.jpg');
  });

  test('backImagePath is replaced when a new path is provided', () async {
    // Stub a card that already has a back image.
    when(() => cardRepo.findById('card-1')).thenAnswer((_) async =>
        _existingCard().copyWith(backImagePath: '/photos/old_back.jpg'));

    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      backImagePath: '/photos/new_back.jpg',
    ));
    expect(result.backImagePath, '/photos/new_back.jpg');
  });

  test('backImagePath is preserved when not provided and not cleared', () async {
    when(() => cardRepo.findById('card-1')).thenAnswer((_) async =>
        _existingCard().copyWith(backImagePath: '/photos/existing_back.jpg'));

    final result = await useCase.execute(UpdateCardInput(cardId: 'card-1'));
    expect(result.backImagePath, '/photos/existing_back.jpg');
  });

  test('backImagePath is cleared to null when clearBackImagePath is true', () async {
    when(() => cardRepo.findById('card-1')).thenAnswer((_) async =>
        _existingCard().copyWith(backImagePath: '/photos/old_back.jpg'));

    final result = await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      clearBackImagePath: true,
    ));
    expect(result.backImagePath, isNull);
  });

  test('deletes the old front image when imagePath is replaced', () async {
    await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      imagePath: '/photos/new_front.jpg',
    ));
    expect(storage.deleted, contains('/photos/card.jpg'));
  });

  test('does not delete the front image when imagePath is unchanged', () async {
    await useCase.execute(UpdateCardInput(cardId: 'card-1'));
    expect(storage.deleted, isEmpty);
  });

  test('deletes the old back image when backImagePath is replaced', () async {
    when(() => cardRepo.findById('card-1')).thenAnswer((_) async =>
        _existingCard().copyWith(backImagePath: '/photos/old_back.jpg'));

    await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      backImagePath: '/photos/new_back.jpg',
    ));
    expect(storage.deleted, contains('/photos/old_back.jpg'));
  });

  test('deletes the old back image when clearBackImagePath is true', () async {
    when(() => cardRepo.findById('card-1')).thenAnswer((_) async =>
        _existingCard().copyWith(backImagePath: '/photos/old_back.jpg'));

    await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      clearBackImagePath: true,
    ));
    expect(storage.deleted, contains('/photos/old_back.jpg'));
  });

  test('calls cardRepo.update exactly once', () async {
    await useCase.execute(UpdateCardInput(
      cardId: 'card-1',
      displayName: '更新',
      memo: null,
      eventIds: const [],
      tagNames: const [],
      xHandles: const [],
      urls: const [],
    ));

    verify(() => cardRepo.update(any())).called(1);
    verifyNever(() => cardRepo.insert(any()));
  });
}
