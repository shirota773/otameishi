import 'dart:typed_data';

import '../services/image_processing_service.dart';
import '../services/ocr_service.dart';
import '../services/service_models.dart';
import '../services/storage_service.dart';

/// Orchestrates the full card capture pipeline.
///
/// When corner detection succeeds:
///   detectCorners → perspectiveCorrect → denoise → encode → save → OCR
///
/// When corner detection fails (low-contrast background, blur, etc):
///   encode (with aspect-ratio-preserving resize) → save → OCR
///
/// In both branches the image's natural aspect ratio is preserved.  OCR
/// failures are non-fatal: the pipeline returns a [CardDraft] with null
/// `ocr`/`extractedData` rather than propagating the error.
class CaptureCardUseCase {
  CaptureCardUseCase({
    required ImageProcessingService imageProcessing,
    required OcrService ocr,
    required StorageService storage,
  })  : _imageProcessing = imageProcessing,
        _ocr = ocr,
        _storage = storage;

  final ImageProcessingService _imageProcessing;
  final OcrService _ocr;
  final StorageService _storage;

  Future<CardDraft> execute(Uint8List rawBytes) async {
    Uint8List pipeline = rawBytes;
    Quad? quad;
    try {
      quad = await _imageProcessing.detectCorners(rawBytes);
    } catch (_) {
      quad = null;
    }

    if (quad != null) {
      try {
        pipeline = await _imageProcessing.perspectiveCorrect(rawBytes, quad);
        pipeline = await _imageProcessing.denoise(pipeline);
      } catch (_) {
        // Degenerate quad / homography failure — fall back to the raw bytes.
        pipeline = rawBytes;
      }
    }

    final encoded = await _imageProcessing.encode(pipeline);
    final imagePath = await _storage.saveCardImage(
      encoded.bytes,
      format: encoded.format,
    );

    OcrResult? ocr;
    ExtractedData? extracted;
    try {
      ocr = await _ocr.recognizeFromPath(imagePath);
      extracted = ExtractedData(
        xHandles: extractXHandles(ocr.fullText),
        urls: extractUrls(ocr.fullText),
        nameCandidate: extractNameCandidate(ocr.lines),
      );
    } catch (_) {
      // OCR failures are non-fatal — the image is already saved.
    }

    return CardDraft(
      imagePath: imagePath,
      ocr: ocr,
      extractedData: extracted,
    );
  }
}
