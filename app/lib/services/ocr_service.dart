import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'service_models.dart';

// ─── Pure extraction helpers (testable without ML Kit) ───────────────────────

final _xHandleRegex = RegExp(r'@[A-Za-z0-9_]{1,15}');
final _urlRegex = RegExp(
  r'https?:\/\/[^\s　、。「」（）()]+',
  caseSensitive: false,
);

List<String> extractXHandles(String text) {
  final matches = _xHandleRegex.allMatches(text);
  final seen = <String>{};
  final result = <String>[];
  for (final m in matches) {
    final handle = m.group(0)!;
    if (seen.add(handle.toLowerCase())) result.add(handle);
  }
  return List.unmodifiable(result);
}

List<String> extractUrls(String text) {
  final matches = _urlRegex.allMatches(text);
  final seen = <String>{};
  final result = <String>[];
  for (final m in matches) {
    final url = _stripTrailingPunctuation(m.group(0)!);
    if (seen.add(url.toLowerCase())) result.add(url);
  }
  return List.unmodifiable(result);
}

String? extractNameCandidate(List<String> lines) {
  for (final raw in lines) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('@')) continue;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) continue;
    final letterCount = trimmed.runes.where(_isLetterLike).length;
    if (letterCount < 1) continue;
    return trimmed;
  }
  return null;
}

bool _isLetterLike(int rune) {
  if (rune >= 0x30 && rune <= 0x39) return true;
  if (rune >= 0x41 && rune <= 0x5A) return true;
  if (rune >= 0x61 && rune <= 0x7A) return true;
  if (rune >= 0x3040 && rune <= 0x30FF) return true;
  if (rune >= 0x4E00 && rune <= 0x9FFF) return true;
  if (rune >= 0xFF66 && rune <= 0xFF9F) return true;
  return false;
}

String _stripTrailingPunctuation(String s) {
  return s.replaceFirst(RegExp(r'[.,;:!?\)\]\}、。]+$'), '');
}

// ─── OCR service ─────────────────────────────────────────────────────────────

abstract interface class MlKitTextRecognizer {
  Future<RecognizedText> processImage(InputImage image);
  Future<void> close();
}

class _RealRecognizer implements MlKitTextRecognizer {
  _RealRecognizer({TextRecognitionScript script = TextRecognitionScript.japanese})
      : _impl = TextRecognizer(script: script);

  final TextRecognizer _impl;

  @override
  Future<RecognizedText> processImage(InputImage image) => _impl.processImage(image);

  @override
  Future<void> close() => _impl.close();
}

abstract interface class OcrService {
  /// Recognizes text from raw image [bytes].  Implementations write the bytes
  /// to a temporary file when the underlying engine (e.g. ML Kit) requires
  /// a file-backed [InputImage].
  Future<OcrResult> recognize(Uint8List bytes);

  /// Recognizes text from an image already on disk.  Preferred call site for
  /// the capture pipeline, which has just saved the file via [StorageService].
  Future<OcrResult> recognizeFromPath(String path);

  Future<void> dispose();
}

class OcrServiceImpl implements OcrService {
  OcrServiceImpl({MlKitTextRecognizer? recognizer})
      : _recognizer = recognizer ?? _RealRecognizer();

  final MlKitTextRecognizer _recognizer;
  static const _uuid = Uuid();

  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'ocr_${_uuid.v4()}.jpg');
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    try {
      return await recognizeFromPath(path);
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  @override
  Future<OcrResult> recognizeFromPath(String path) async {
    final recognized =
        await _recognizer.processImage(InputImage.fromFilePath(path));
    final lines = recognized.blocks
        .expand((b) => b.lines.map((l) => l.text))
        .toList(growable: false);
    return OcrResult(fullText: recognized.text, lines: List.unmodifiable(lines));
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
