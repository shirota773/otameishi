import '../db/repositories/card_repository.dart';
import '../services/storage_service.dart';

/// Deletes a card by id and cleans up its image files.
///
/// DB-side cascades handle business_card_tags / business_card_events and the
/// FTS index.  Image files live in the app sandbox and must be removed
/// explicitly — failures are swallowed (best-effort cleanup).
class DeleteCardUseCase {
  const DeleteCardUseCase({
    required CardRepository cardRepo,
    required StorageService storage,
  })  : _cardRepo = cardRepo,
        _storage = storage;

  final CardRepository _cardRepo;
  final StorageService _storage;

  Future<void> execute(String cardId) async {
    final card = await _cardRepo.findById(cardId);
    if (card == null) return;

    await _cardRepo.delete(cardId);

    await _maybeDelete(card.imagePath);
    final back = card.backImagePath;
    if (back != null && back.isNotEmpty) {
      await _maybeDelete(back);
    }
  }

  Future<void> _maybeDelete(String path) async {
    try {
      await _storage.deleteCardImage(path);
    } catch (_) {
      // Best-effort — orphaned image is preferable to a failed delete.
    }
  }
}
