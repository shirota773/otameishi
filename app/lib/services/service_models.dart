import 'dart:typed_data';

/// Immutable 2D point used by image-processing services.
class Point2D {
  const Point2D(this.x, this.y);
  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point2D && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Point2D($x, $y)';
}

/// Immutable quadrilateral: the four corners of a detected card.
/// Order: topLeft → topRight → bottomRight → bottomLeft (clockwise from TL).
class Quad {
  const Quad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  final Point2D topLeft;
  final Point2D topRight;
  final Point2D bottomRight;
  final Point2D bottomLeft;
}

/// Supported image encoding formats for card persistence.
enum ImageFormat { jpeg, webp }

/// Encoded image bytes plus metadata about the encoding.
class EncodedImage {
  const EncodedImage({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
  });

  final Uint8List bytes;
  final ImageFormat format;
  final int width;
  final int height;
}

/// Result of OCR text recognition on a card image.
class OcrResult {
  const OcrResult({required this.fullText, required this.lines});

  final String fullText;
  final List<String> lines;
}

/// Post-processed extraction from an [OcrResult].
class ExtractedData {
  const ExtractedData({
    required this.xHandles,
    required this.urls,
    this.nameCandidate,
  });

  /// X (Twitter) handles found, including the leading `@`.
  final List<String> xHandles;

  /// Generic URLs found.
  final List<String> urls;

  /// Best guess at a display name (typically the first non-handle, non-URL line).
  final String? nameCandidate;

  static const _absent = Object();

  ExtractedData copyWith({
    List<String>? xHandles,
    List<String>? urls,
    Object? nameCandidate = _absent,
  }) =>
      ExtractedData(
        xHandles: xHandles ?? this.xHandles,
        urls: urls ?? this.urls,
        nameCandidate: identical(nameCandidate, _absent)
            ? this.nameCandidate
            : nameCandidate as String?,
      );
}

/// Kind of SNS service a URL points at.
enum SnsKind { x, instagram, discord, web }

/// QR payload decoded from a card image.
class QrPayload {
  const QrPayload({
    required this.rawValue,
    this.parsedUrl,
    required this.snsKind,
  });

  final String rawValue;
  final Uri? parsedUrl;
  final SnsKind snsKind;
}

/// Draft card produced by the capture pipeline.  UI confirms before persisting.
class CardDraft {
  const CardDraft({
    required this.imagePath,
    this.ocr,
    this.extractedData,
    this.qr,
  });

  final String imagePath;
  final OcrResult? ocr;
  final ExtractedData? extractedData;
  final QrPayload? qr;

  static const _absent = Object();

  CardDraft copyWith({
    String? imagePath,
    Object? ocr = _absent,
    Object? extractedData = _absent,
    Object? qr = _absent,
  }) =>
      CardDraft(
        imagePath: imagePath ?? this.imagePath,
        ocr: identical(ocr, _absent) ? this.ocr : ocr as OcrResult?,
        extractedData: identical(extractedData, _absent)
            ? this.extractedData
            : extractedData as ExtractedData?,
        qr: identical(qr, _absent) ? this.qr : qr as QrPayload?,
      );
}
