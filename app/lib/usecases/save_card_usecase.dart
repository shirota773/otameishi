import 'package:uuid/uuid.dart';

import '../db/repositories/card_repository.dart';
import '../db/repositories/event_repository.dart';
import '../db/repositories/tag_repository.dart';
import '../models/business_card.dart';
import '../models/event.dart';
import '../models/tag.dart';
import '../services/service_models.dart';

/// Input to [SaveCardUseCase.execute].
///
/// [xHandles] / [urls] overrides: when non-null, they REPLACE the values
/// in `draft.extractedData`.  This lets the review screen pass the
/// user-edited final lists without having to mutate the draft.  When null,
/// the values from `draft.extractedData` are used.
class SaveCardInput {
  const SaveCardInput({
    required this.draft,
    this.displayName,
    this.memo,
    this.eventIds = const [],
    this.tagNames = const [],
    this.xHandles,
    this.urls,
    this.extraSnsLinks = const [],
    this.backImagePath,
    this.isMyCard = false,
  });

  final CardDraft draft;
  final String? displayName;
  final String? memo;

  /// IDs of events this card should be linked to (many-to-many).
  final List<String> eventIds;

  final List<String> tagNames;
  final List<String>? xHandles;
  final List<String>? urls;
  final List<String> extraSnsLinks;

  /// Optional file-system path to the back-side card image.
  final String? backImagePath;

  /// When true, the saved card will be flagged as the user's own profile card.
  /// [CardRepository.setMyCard] is called after insert to ensure mutual exclusion.
  final bool isMyCard;
}

class SaveCardUseCase {
  SaveCardUseCase({
    required CardRepository cardRepository,
    required TagRepository tagRepository,
    required EventRepository eventRepository,
  })  : _cardRepo = cardRepository,
        _tagRepo = tagRepository,
        _eventRepo = eventRepository;

  final CardRepository _cardRepo;
  final TagRepository _tagRepo;
  final EventRepository _eventRepo;

  static const _uuid = Uuid();

  Future<BusinessCard> execute(SaveCardInput input) async {
    // Resolve tags, skipping blank names.  findOrCreate is case-insensitive.
    final resolvedTags = <Tag>[];
    for (final raw in input.tagNames) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      resolvedTags.add(await _tagRepo.findOrCreate(trimmed));
    }

    // Resolve events by id.  Events that are not found are silently skipped.
    final resolvedEvents = <Event>[];
    for (final id in input.eventIds) {
      final event = await _eventRepo.findById(id);
      if (event != null) resolvedEvents.add(event);
    }

    // Build SNS links list. Caller's `xHandles` / `urls` win over the draft's
    // extracted values; `extraSnsLinks` always appends.
    final handles =
        input.xHandles ?? input.draft.extractedData?.xHandles ?? const [];
    final urls = input.urls ?? input.draft.extractedData?.urls ?? const [];
    final snsLinks = <String>[...handles, ...urls, ...input.extraSnsLinks];

    final card = BusinessCard(
      id: _uuid.v4(),
      imagePath: input.draft.imagePath,
      backImagePath: input.backImagePath,
      displayName: input.displayName ?? input.draft.extractedData?.nameCandidate,
      snsLinks: List.unmodifiable(snsLinks),
      memo: input.memo,
      events: List.unmodifiable(resolvedEvents),
      createdAt: DateTime.now().toUtc(),
      tags: List.unmodifiable(resolvedTags),
      isMyCard: input.isMyCard,
    );

    await _cardRepo.insert(card);
    // setMyCard enforces mutual exclusion (clears any prior my-card flag).
    if (input.isMyCard) {
      await _cardRepo.setMyCard(card.id);
    }
    return card;
  }
}
