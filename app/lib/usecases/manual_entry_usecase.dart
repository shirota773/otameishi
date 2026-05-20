import 'dart:typed_data';

import '../services/image_processing_service.dart';
import '../services/service_models.dart';
import '../services/storage_service.dart';

/// Builds a [CardDraft] from raw image bytes without running OCR or
/// perspective correction.
///
/// Used by the manual-entry flow (＋ボタン → アルバムから手入力): the image
/// is just resized to fit 1920px / 1MB and saved.  OCR/extracted data are
/// always null — the user types in everything on the review screen.
class ManualEntryUseCase {
  const ManualEntryUseCase({
    required ImageProcessingService imageProcessing,
    required StorageService storage,
  })  : _imageProcessing = imageProcessing,
        _storage = storage;

  final ImageProcessingService _imageProcessing;
  final StorageService _storage;

  Future<CardDraft> execute(Uint8List rawBytes) async {
    final encoded = await _imageProcessing.encode(rawBytes);
    final imagePath = await _storage.saveCardImage(
      encoded.bytes,
      format: encoded.format,
    );
    return CardDraft(imagePath: imagePath);
  }
}
