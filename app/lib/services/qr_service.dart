import 'service_models.dart';
import 'sns_launcher_service.dart';

/// Decodes QR barcodes scanned via the camera overlay.
///
/// `mobile_scanner` v5 exposes QR decoding through its camera-attached
/// `MobileScanner` widget, not as a bytes-in API.  The frontend's capture
/// review screen receives QR results from the scanner widget directly and
/// passes them here via [decodePayload] to apply SNS classification and URL
/// parsing.  This service therefore has no Uint8List path in production.
abstract interface class QrService {
  /// Parses a raw scanner string into a [QrPayload], or null if empty.
  QrPayload? decodePayload(String rawValue);
}

class QrServiceImpl implements QrService {
  const QrServiceImpl();

  @override
  QrPayload? decodePayload(String rawValue) {
    final trimmed = rawValue.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    final kind =
        (uri != null && uri.hasScheme) ? classifySnsUrl(trimmed) : SnsKind.web;
    return QrPayload(
      rawValue: trimmed,
      parsedUrl: uri,
      snsKind: kind,
    );
  }
}
