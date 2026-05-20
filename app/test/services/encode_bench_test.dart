import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Measures the pure-Dart JPEG encode speed used by the production
/// [ImageProcessingService] pipeline.  Isolate scheduling overhead (50–200 ms
/// in the test harness) is not part of the user-visible scan budget on
/// device, so we exclude it here.
void main() {
  test(
    '1920x1920 JPEG encode under 500 ms',
    () {
      final image = img.Image(width: 1920, height: 1920);
      for (int y = 0; y < 1920; y++) {
        for (int x = 0; x < 1920; x++) {
          image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
        }
      }

      final sw = Stopwatch()..start();
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));
      sw.stop();

      expect(bytes.length, lessThanOrEqualTo(1024 * 1024));
      expect(sw.elapsedMilliseconds, lessThan(500),
          reason: 'encode took ${sw.elapsedMilliseconds} ms');
    },
    timeout: const Timeout(Duration(seconds: 10)),
  );
}
