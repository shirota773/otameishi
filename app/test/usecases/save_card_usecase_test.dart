import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:otameishi/db/repositories/card_repository.dart';
import 'package:otameishi/db/repositories/event_repository.dart';
import 'package:otameishi/db/repositories/tag_repository.dart';
import 'package:otameishi/models/business_card.dart';
import 'package:otameishi/models/event.dart';
import 'package:otameishi/models/tag.dart';
import 'package:otameishi/services/service_models.dart';
import 'package:otameishi/usecases/save_card_usecase.dart';

class _MockCardRepo extends Mock implements CardRepository {}

class _MockTagRepo extends Mock implements TagRepository {}

class _MockEventRepo extends Mock implements EventRepository {}

Tag _tag(String id, String name) => Tag(id: id, name: name);

Event _event(String id, String name) => Event(id: id, name: name);

BusinessCard _card() => BusinessCard(
      id: 'x',
      imagePath: '/p',
      snsLinks: const [],
      events: const [],
      createdAt: DateTime.utc(2026),
      tags: const [],
    );

CardDraft _draft({
  List<String> xHandles = const [],
  List<String> urls = const [],
  String? nameCandidate,
}) =>
    CardDraft(
      imagePath: '/mock/card.jpg',
      ocr: const OcrResult(fullText: '', lines: []),
      extractedData: ExtractedData(
        xHandles: xHandles,
        urls: urls,
        nameCandidate: nameCandidate,
      ),
    );

void main() {
  late _MockCardRepo cardRepo;
  late _MockTagRepo tagRepo;
  late _MockEventRepo eventRepo;
  late SaveCardUseCase useCase;

  setUpAll(() {
    registerFallbackValue(_card());
    registerFallbackValue(_tag('x', 'x'));
    registerFallbackValue(_event('x', 'x'));
  });

  setUp(() {
    cardRepo = _MockCardRepo();
    tagRepo = _MockTagRepo();
    eventRepo = _MockEventRepo();
    useCase = SaveCardUseCase(
      cardRepository: cardRepo,
      tagRepository: tagRepo,
      eventRepository: eventRepo,
    );
    when(() => cardRepo.insert(any())).thenAnswer((_) async {});
  });

  test('persists a card and returns it', () async {
    final card = await useCase.execute(SaveCardInput(draft: _draft()));
    expect(card.imagePath, '/mock/card.jpg');
    verify(() => cardRepo.insert(any())).called(1);
  });

  test('resolves each non-blank tag name through findOrCreate', () async {
    when(() => tagRepo.findOrCreate('oshi'))
        .thenAnswer((_) async => _tag('t1', 'oshi'));
    when(() => tagRepo.findOrCreate('vtuber'))
        .thenAnswer((_) async => _tag('t2', 'vtuber'));

    final card = await useCase.execute(SaveCardInput(
      draft: _draft(),
      tagNames: ['oshi', '  ', '', 'vtuber'],
    ));

    verify(() => tagRepo.findOrCreate('oshi')).called(1);
    verify(() => tagRepo.findOrCreate('vtuber')).called(1);
    verifyNever(() => tagRepo.findOrCreate(''));
    expect(card.tags.map((t) => t.name), ['oshi', 'vtuber']);
  });

  test('uses extracted name candidate when displayName not provided', () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(nameCandidate: '田中'),
    ));
    expect(card.displayName, '田中');
  });

  test('explicit displayName wins over extracted candidate', () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(nameCandidate: 'auto'),
      displayName: 'manual',
    ));
    expect(card.displayName, 'manual');
  });

  test('snsLinks combines handles + urls + extras', () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(
        xHandles: ['@a', '@b'],
        urls: ['https://x.com/a'],
      ),
      extraSnsLinks: ['https://example.com'],
    ));
    expect(card.snsLinks, ['@a', '@b', 'https://x.com/a', 'https://example.com']);
  });

  test('input.xHandles overrides draft.extractedData.xHandles when provided',
      () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(xHandles: ['@ocr1', '@ocr2'], urls: ['https://ocr.com']),
      xHandles: ['@user_edited'],
      urls: ['https://user.com'],
    ));
    expect(card.snsLinks, ['@user_edited', 'https://user.com']);
  });

  test('empty xHandles/urls explicitly clears the OCR-extracted values',
      () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(xHandles: ['@ocr'], urls: ['https://ocr.com']),
      xHandles: const [],
      urls: const [],
    ));
    expect(card.snsLinks, isEmpty);
  });

  test('memo propagates to card', () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(),
      memo: '解釈一致',
    ));
    expect(card.memo, '解釈一致');
  });

  test('eventIds resolved to events and attached to card', () async {
    when(() => eventRepo.findById('evt-1'))
        .thenAnswer((_) async => _event('evt-1', 'Comiket'));
    when(() => eventRepo.findById('evt-2'))
        .thenAnswer((_) async => _event('evt-2', 'にじフェス'));

    final card = await useCase.execute(SaveCardInput(
      draft: _draft(),
      eventIds: ['evt-1', 'evt-2'],
    ));
    expect(card.events.length, 2);
    expect(card.events.map((e) => e.id).toSet(), {'evt-1', 'evt-2'});
  });

  test('unknown event id is silently skipped', () async {
    when(() => eventRepo.findById('ghost')).thenAnswer((_) async => null);

    final card = await useCase.execute(SaveCardInput(
      draft: _draft(),
      eventIds: ['ghost'],
    ));
    expect(card.events, isEmpty);
  });

  test('no eventIds yields empty events list', () async {
    final card = await useCase.execute(SaveCardInput(draft: _draft()));
    expect(card.events, isEmpty);
  });

  test('backImagePath propagates to card when provided', () async {
    final card = await useCase.execute(SaveCardInput(
      draft: _draft(),
      backImagePath: '/photos/card_back.jpg',
    ));
    expect(card.backImagePath, '/photos/card_back.jpg');
  });

  test('backImagePath is null when not provided', () async {
    final card = await useCase.execute(SaveCardInput(draft: _draft()));
    expect(card.backImagePath, isNull);
  });

  test('createdAt is set to roughly now', () async {
    final before = DateTime.now().toUtc();
    final card = await useCase.execute(SaveCardInput(draft: _draft()));
    final after = DateTime.now().toUtc();
    expect(card.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue);
    expect(card.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue);
  });
}
