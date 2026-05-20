import '../db/repositories/card_repository.dart';
import '../db/repositories/event_repository.dart';
import '../db/repositories/tag_repository.dart';
import '../models/business_card.dart';
import '../models/event.dart';
import '../models/tag.dart';
import '../services/storage_service.dart';

/// Input to [UpdateCardUseCase.execute].
///
/// All fields replace the existing card's values.  Pass empty lists to clear
/// tags / events / snsLinks.  Pass null for [displayName] / [memo] to clear
/// those fields.
class UpdateCardInput {
  const UpdateCardInput({
    required this.cardId,
    this.displayName,
    this.memo,
    this.eventIds = const [],
    this.tagNames = const [],
    this.xHandles = const [],
    this.urls = const [],
    this.imagePath,
    this.backImagePath,
    this.clearBackImagePath = false,
  });

  final String cardId;
  final String? displayName;
  final String? memo;
  final List<String> eventIds;
  final List<String> tagNames;
  final List<String> xHandles;
  final List<String> urls;

  /// Replacement file-system path for the front-side image, or null to leave
  /// the existing path unchanged.  The front image is required and cannot be
  /// cleared.
  final String? imagePath;

  /// New file-system path for the back-side image, or null to leave unchanged.
  /// Set [clearBackImagePath] to true to explicitly remove the back image.
  final String? backImagePath;

  /// When true, [backImagePath] on the updated card is set to null regardless
  /// of the value of [backImagePath].
  final bool clearBackImagePath;
}

/// Updates an existing [BusinessCard] in place, preserving [imagePath] and
/// [createdAt] while replacing all other user-editable fields.
class UpdateCardUseCase {
  UpdateCardUseCase({
    required CardRepository cardRepository,
    required TagRepository tagRepository,
    required EventRepository eventRepository,
    required StorageService storage,
  })  : _cardRepo = cardRepository,
        _tagRepo = tagRepository,
        _eventRepo = eventRepository,
        _storage = storage;

  final CardRepository _cardRepo;
  final TagRepository _tagRepo;
  final EventRepository _eventRepo;
  final StorageService _storage;

  Future<BusinessCard> execute(UpdateCardInput input) async {
    final existing = await _cardRepo.findById(input.cardId);
    if (existing == null) {
      throw StateError('No card found with id ${input.cardId}');
    }

    final resolvedTags = <Tag>[];
    for (final raw in input.tagNames) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) continue;
      resolvedTags.add(await _tagRepo.findOrCreate(trimmed));
    }

    final resolvedEvents = <Event>[];
    for (final id in input.eventIds) {
      final event = await _eventRepo.findById(id);
      if (event != null) resolvedEvents.add(event);
    }

    final snsLinks = <String>[...input.xHandles, ...input.urls];

    // Construct directly rather than copyWith because copyWith uses `??` and
    // cannot clear nullable fields (displayName, memo, backImagePath) to null.
    final resolvedBackImagePath = input.clearBackImagePath
        ? null
        : (input.backImagePath ?? existing.backImagePath);

    final updated = BusinessCard(
      id: existing.id,
      imagePath: input.imagePath ?? existing.imagePath,
      backImagePath: resolvedBackImagePath,
      createdAt: existing.createdAt,
      displayName: input.displayName,
      memo: input.memo,
      snsLinks: List.unmodifiable(snsLinks),
      tags: List.unmodifiable(resolvedTags),
      events: List.unmodifiable(resolvedEvents),
    );

    await _cardRepo.update(updated);

    // Reclaim storage from images that are no longer referenced.  Best-effort:
    // we swallow failures so a stale file never blocks a successful DB update.
    await _maybeDelete(existing.imagePath, updated.imagePath);
    await _maybeDelete(existing.backImagePath, updated.backImagePath);

    return updated;
  }

  Future<void> _maybeDelete(String? oldPath, String? newPath) async {
    if (oldPath == null) return;
    if (oldPath == newPath) return;
    try {
      await _storage.deleteCardImage(oldPath);
    } catch (_) {
      // Ignore: orphan cleanup is non-critical.
    }
  }
}
