import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:otameishi/services/image_processing_service.dart';
import 'package:otameishi/services/service_models.dart';

Uint8List _syntheticJpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// White card on a black background — corner detection should fire here.
Uint8List _cardOnBgJpeg({
  int imgW = 400,
  int imgH = 300,
  int cardLeft = 60,
  int cardTop = 50,
  int cardW = 280,
  int cardH = 200,
}) {
  final image = img.Image(width: imgW, height: imgH);
  for (int y = 0; y < imgH; y++) {
    for (int x = 0; x < imgW; x++) {
      final inside = x >= cardLeft &&
          x < cardLeft + cardW &&
          y >= cardTop &&
          y < cardTop + cardH;
      final v = inside ? 240 : 20;
      image.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  const service = ImageProcessingServiceImpl();

  group('encode()', () {
    test('fits within maxDimension', () async {
      final bytes = _syntheticJpeg(1920, 1920);
      final result = await service.encode(bytes);
      expect(result.width, lessThanOrEqualTo(kMaxDimension));
      expect(result.height, lessThanOrEqualTo(kMaxDimension));
    });

    test('downscales oversized while preserving aspect ratio', () async {
      final bytes = _syntheticJpeg(3000, 2000);
      final result = await service.encode(bytes);
      expect(result.width, lessThanOrEqualTo(kMaxDimension));
      expect(result.height, lessThanOrEqualTo(kMaxDimension));
      // Source aspect 3:2. Allow 1px rounding on either side.
      final aspect = result.width / result.height;
      expect(aspect, closeTo(3 / 2, 0.01));
    });

    test('caps only the longest side, not both independently', () async {
      // Source 4032x3024 (real phone photo) must not become 1920x1920.
      final bytes = _syntheticJpeg(4032, 3024);
      final result = await service.encode(bytes);
      expect(result.width, lessThanOrEqualTo(kMaxDimension));
      expect(result.height, lessThanOrEqualTo(kMaxDimension));
      expect(result.width, isNot(equals(result.height)),
          reason: 'a 4:3 input must not collapse to a square output');
    });

    test('fits within maxFileBytes', () async {
      final bytes = _syntheticJpeg(1920, 1920);
      final result = await service.encode(bytes);
      expect(result.bytes.length, lessThanOrEqualTo(kMaxFileBytes));
    });

    test('does not upscale small image', () async {
      final bytes = _syntheticJpeg(400, 300);
      final result = await service.encode(bytes);
      expect(result.width, lessThanOrEqualTo(400));
      expect(result.height, lessThanOrEqualTo(300));
    });
  });

  group('perspectiveCorrect()', () {
    test('produces approximately correct dimensions for axis-aligned quad',
        () async {
      final bytes = _syntheticJpeg(400, 300);
      const quad = Quad(
        topLeft: Point2D(50, 50),
        topRight: Point2D(250, 50),
        bottomRight: Point2D(250, 150),
        bottomLeft: Point2D(50, 150),
      );
      final out = await service.perspectiveCorrect(bytes, quad);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, inInclusiveRange(199, 201));
      expect(decoded.height, inInclusiveRange(99, 101));
    });

    test('preserves aspect ratio when quad is the full image (4:3)', () async {
      // This simulates the "detection failed, use full image" fallback in v1.
      // The bug: output was forced to 1920x1920. The fix: preserve 4:3.
      final bytes = _syntheticJpeg(4032, 3024);
      const quad = Quad(
        topLeft: Point2D(0, 0),
        topRight: Point2D(4031, 0),
        bottomRight: Point2D(4031, 3023),
        bottomLeft: Point2D(0, 3023),
      );
      final out = await service.perspectiveCorrect(bytes, quad);
      final decoded = img.decodeImage(out)!;
      expect(decoded.width, lessThanOrEqualTo(kMaxDimension));
      expect(decoded.height, lessThanOrEqualTo(kMaxDimension));
      final aspect = decoded.width / decoded.height;
      expect(aspect, closeTo(4 / 3, 0.02),
          reason: 'output must keep source aspect ratio');
    });

    test('preserves aspect ratio for a 91:55 card quad', () async {
      // Approximate business card aspect on a 4000x3000 photo.
      final bytes = _syntheticJpeg(4000, 3000);
      const quad = Quad(
        topLeft: Point2D(500, 1000),
        topRight: Point2D(500 + 1820, 1000),
        bottomRight: Point2D(500 + 1820, 1000 + 1100),
        bottomLeft: Point2D(500, 1000 + 1100),
      );
      final out = await service.perspectiveCorrect(bytes, quad);
      final decoded = img.decodeImage(out)!;
      final aspect = decoded.width / decoded.height;
      expect(aspect, closeTo(1820 / 1100, 0.03));
    });
  });

  group('denoise()', () {
    test('returns decodable JPEG', () async {
      final bytes = _syntheticJpeg(200, 200);
      final result = await service.denoise(bytes);
      expect(img.decodeImage(result), isNotNull);
    });
  });

  group('detectCorners()', () {
    test('returns Quad or null without throwing', () async {
      final bytes = _syntheticJpeg(400, 300);
      await service.detectCorners(bytes);
    });

    test('rejects an image that is just gradient noise', () async {
      // The pre-fix detector returned full-image bbox for any noisy frame.
      final bytes = _syntheticJpeg(400, 300);
      final quad = await service.detectCorners(bytes);
      // Gradient pattern → uniform edges everywhere → should be rejected
      // because the bounding box covers >95% of the thumb.
      expect(quad, isNull);
    });

    test('detects a clear white card on black background', () async {
      final bytes = _cardOnBgJpeg();
      final quad = await service.detectCorners(bytes);
      expect(quad, isNotNull, reason: 'should find the card edges');
      // Detected corners should roughly enclose the synthetic card (60,50)–(340,250).
      final q = quad!;
      expect(q.topLeft.x, inInclusiveRange(40, 80));
      expect(q.topLeft.y, inInclusiveRange(30, 70));
      expect(q.bottomRight.x, inInclusiveRange(320, 360));
      expect(q.bottomRight.y, inInclusiveRange(230, 270));
    });
  });
}
