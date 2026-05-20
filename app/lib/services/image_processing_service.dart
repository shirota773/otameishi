import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'service_models.dart';

// ─── Tunables ────────────────────────────────────────────────────────────────

const int kMaxDimension = 1920;
const int kMaxFileBytes = 1024 * 1024;
const int _kDefaultJpegQuality = 85;
const int _kMinJpegQuality = 40;
const int _kQualityStep = 10;
const int _kCornerDetectionThumbDim = 400;
const int _kMinEdgeSpan = 40;
const int _kMaxDownscaleSteps = 5;

// Largest fraction of the thumb a detected card can cover. Above this we
// assume detection just found image noise across the whole frame.
const double _kMaxBoundaryFill = 0.95;
// Smallest fraction of the thumb a detected card must cover.
const double _kMinBoundaryFill = 0.10;

class ImageProcessingException implements Exception {
  const ImageProcessingException(this.message);
  final String message;
  @override
  String toString() => 'ImageProcessingException: $message';
}

// ─── Service interface ───────────────────────────────────────────────────────

abstract interface class ImageProcessingService {
  /// Best-effort corner detection.  Returns null when no convincing card
  /// edges are found; the caller should fall back to using the original image.
  Future<Quad?> detectCorners(Uint8List bytes);

  /// Warps the [quad] region into an axis-aligned rectangle.  Output
  /// dimensions preserve the quad's natural aspect ratio (long side capped
  /// at [kMaxDimension]).
  Future<Uint8List> perspectiveCorrect(Uint8List bytes, Quad quad);

  /// Mild denoise (Gaussian blur).
  Future<Uint8List> denoise(Uint8List bytes);

  /// Resizes (if needed) and encodes the image so the result is within
  /// [maxDimension] (longest side) and [maxFileBytes].  Aspect ratio is
  /// always preserved.
  Future<EncodedImage> encode(
    Uint8List bytes, {
    ImageFormat format,
    int maxDimension,
    int maxFileBytes,
  });
}

class ImageProcessingServiceImpl implements ImageProcessingService {
  const ImageProcessingServiceImpl();

  @override
  Future<Quad?> detectCorners(Uint8List bytes) =>
      Isolate.run(() => _detectCornersSync(bytes));

  @override
  Future<Uint8List> perspectiveCorrect(Uint8List bytes, Quad quad) =>
      Isolate.run(() => _perspectiveSync(bytes, quad));

  @override
  Future<Uint8List> denoise(Uint8List bytes) =>
      Isolate.run(() => _denoiseSync(bytes));

  @override
  Future<EncodedImage> encode(
    Uint8List bytes, {
    ImageFormat format = ImageFormat.jpeg,
    int maxDimension = kMaxDimension,
    int maxFileBytes = kMaxFileBytes,
  }) =>
      Isolate.run(() => _encodeSync(bytes, format, maxDimension, maxFileBytes));
}

// ─── Decode + scale helpers ──────────────────────────────────────────────────

img.Image _decode(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const ImageProcessingException('Could not decode image bytes');
  }
  return decoded;
}

img.Image _resizeToFit(img.Image src, int maxDim) {
  if (src.width <= maxDim && src.height <= maxDim) return src;
  final scale = maxDim / math.max(src.width, src.height);
  return img.copyResize(
    src,
    width: (src.width * scale).round(),
    height: (src.height * scale).round(),
    interpolation: img.Interpolation.linear,
  );
}

// ─── Encode (aspect-ratio preserving) ────────────────────────────────────────

EncodedImage _encodeSync(
  Uint8List bytes,
  ImageFormat format,
  int maxDimension,
  int maxFileBytes,
) {
  img.Image current = _resizeToFit(_decode(bytes), maxDimension);
  int quality = _kDefaultJpegQuality;
  int downscaleSteps = 0;
  Uint8List out;

  while (true) {
    out = Uint8List.fromList(img.encodeJpg(current, quality: quality));
    if (out.length <= maxFileBytes) break;
    quality -= _kQualityStep;
    if (quality < _kMinJpegQuality) {
      // Downscale and reset quality. Bound the outer loop to avoid pathological
      // inputs (e.g. uniform-colour images that don't shrink with quality) from
      // looping indefinitely.
      downscaleSteps++;
      if (downscaleSteps > _kMaxDownscaleSteps) break;
      final newDim = (math.max(current.width, current.height) * 0.8).round();
      if (newDim < 100) break;
      current = _resizeToFit(current, newDim);
      quality = _kDefaultJpegQuality;
    }
  }

  return EncodedImage(
    bytes: out,
    format: format,
    width: current.width,
    height: current.height,
  );
}

Uint8List _denoiseSync(Uint8List bytes) {
  final src = _decode(bytes);
  final blurred = img.gaussianBlur(src, radius: 2);
  return Uint8List.fromList(img.encodeJpg(blurred, quality: _kDefaultJpegQuality));
}

// ─── Corner detection ────────────────────────────────────────────────────────

/// Two-pass detection on a downscaled thumb:
///   1) Sobel-like gradient magnitude
///   2) Otsu threshold the magnitudes → binary edge map
///   3) Project edges onto rows/columns to find a card-like rectangle
/// Returns null when the result looks like full-image noise or no edges.
Quad? _detectCornersSync(Uint8List bytes) {
  final src = _decode(bytes);
  final thumb = _resizeToFit(src, _kCornerDetectionThumbDim);
  final gray = img.grayscale(thumb);
  final smoothed = img.gaussianBlur(gray, radius: 1);

  final w = smoothed.width;
  final h = smoothed.height;
  final grad = Uint16List(w * h);
  int maxGrad = 0;

  for (int y = 1; y < h - 1; y++) {
    for (int x = 1; x < w - 1; x++) {
      final l = smoothed.getPixel(x - 1, y).r.toInt();
      final r = smoothed.getPixel(x + 1, y).r.toInt();
      final t = smoothed.getPixel(x, y - 1).r.toInt();
      final b = smoothed.getPixel(x, y + 1).r.toInt();
      final mag = (l - r).abs() + (t - b).abs();
      grad[y * w + x] = mag;
      if (mag > maxGrad) maxGrad = mag;
    }
  }

  if (maxGrad < 8) return null;

  final threshold = _otsuThreshold(grad, maxGrad);
  if (threshold == 0) return null;

  // Row + column edge-pixel counts.
  final rowSums = Int32List(h);
  final colSums = Int32List(w);
  for (int y = 0; y < h; y++) {
    int rs = 0;
    for (int x = 0; x < w; x++) {
      if (grad[y * w + x] > threshold) {
        rs++;
        colSums[x]++;
      }
    }
    rowSums[y] = rs;
  }

  final rowMedian = _median(rowSums);
  final colMedian = _median(colSums);
  // Edges must be visibly denser than the median noise floor.
  final rowMin = math.max(rowMedian * 2, 3);
  final colMin = math.max(colMedian * 2, 3);

  int? firstAbove(Int32List xs, int minCount, {bool reverse = false}) {
    if (reverse) {
      for (int i = xs.length - 1; i >= 0; i--) {
        if (xs[i] >= minCount) return i;
      }
    } else {
      for (int i = 0; i < xs.length; i++) {
        if (xs[i] >= minCount) return i;
      }
    }
    return null;
  }

  final top = firstAbove(rowSums, rowMin);
  final bottom = firstAbove(rowSums, rowMin, reverse: true);
  final left = firstAbove(colSums, colMin);
  final right = firstAbove(colSums, colMin, reverse: true);

  if (top == null || bottom == null || left == null || right == null) {
    return null;
  }
  final spanW = right - left;
  final spanH = bottom - top;
  if (spanW < _kMinEdgeSpan || spanH < _kMinEdgeSpan) return null;

  // Reject "full-frame noise" — if the detected rect basically fills the thumb,
  // it's almost certainly not a card edge.
  final fill = (spanW * spanH) / (w * h);
  if (fill > _kMaxBoundaryFill) return null;
  if (fill < _kMinBoundaryFill) return null;

  final sx = src.width / thumb.width;
  final sy = src.height / thumb.height;

  return Quad(
    topLeft: Point2D(left * sx, top * sy),
    topRight: Point2D(right * sx, top * sy),
    bottomRight: Point2D(right * sx, bottom * sy),
    bottomLeft: Point2D(left * sx, bottom * sy),
  );
}

/// Otsu's method on a histogram of [maxVal+1] bins (or 256, whichever is
/// smaller).  Returns the threshold value in the original units of [values].
int _otsuThreshold(Uint16List values, int maxVal) {
  final bins = math.min(maxVal + 1, 256);
  final hist = Int32List(bins);
  final scale = (bins - 1) / maxVal;
  for (final v in values) {
    if (v == 0) continue;
    final b = (v * scale).round();
    hist[b]++;
  }
  int total = 0;
  double sum = 0;
  for (int i = 0; i < bins; i++) {
    total += hist[i];
    sum += i * hist[i].toDouble();
  }
  if (total == 0) return 0;

  double sumB = 0;
  int wB = 0;
  double varMax = 0;
  int threshold = 0;
  for (int i = 0; i < bins; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += i * hist[i].toDouble();
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > varMax) {
      varMax = between;
      threshold = i;
    }
  }
  return (threshold / scale).round();
}

int _median(Int32List values) {
  final sorted = Int32List.fromList(values)..sort();
  return sorted[sorted.length ~/ 2];
}

// ─── Perspective correction (aspect-ratio preserving) ────────────────────────

Uint8List _perspectiveSync(Uint8List bytes, Quad quad) {
  final src = _decode(bytes);

  double dist(Point2D a, Point2D b) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  final wTop = dist(quad.topLeft, quad.topRight);
  final wBot = dist(quad.bottomLeft, quad.bottomRight);
  final hL = dist(quad.topLeft, quad.bottomLeft);
  final hR = dist(quad.topRight, quad.bottomRight);

  final quadW = math.max(wTop, wBot);
  final quadH = math.max(hL, hR);

  if (quadW < 1 || quadH < 1) {
    throw const ImageProcessingException('Degenerate quad');
  }

  // Cap the longer dimension at kMaxDimension and scale the other to keep
  // the natural aspect ratio of the quad.
  int outW;
  int outH;
  if (quadW >= quadH) {
    outW = math.min(quadW.round(), kMaxDimension);
    outH = (outW * quadH / quadW).round().clamp(1, kMaxDimension);
  } else {
    outH = math.min(quadH.round(), kMaxDimension);
    outW = (outH * quadW / quadH).round().clamp(1, kMaxDimension);
  }

  final dst = img.Image(width: outW, height: outH);

  // Inverse homography: output rect → input quad. We sample input pixels for
  // each output pixel.
  final H = _computeHomography(
    srcPts: [
      const Point2D(0, 0),
      Point2D(outW.toDouble(), 0),
      Point2D(outW.toDouble(), outH.toDouble()),
      Point2D(0, outH.toDouble()),
    ],
    dstPts: [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft],
  );

  for (int y = 0; y < outH; y++) {
    for (int x = 0; x < outW; x++) {
      final w = H[6] * x + H[7] * y + H[8];
      if (w.abs() < 1e-10) continue;
      final sxF = (H[0] * x + H[1] * y + H[2]) / w;
      final syF = (H[3] * x + H[4] * y + H[5]) / w;
      final sxR = sxF.round();
      final syR = syF.round();
      if (sxR >= 0 && sxR < src.width && syR >= 0 && syR < src.height) {
        dst.setPixel(x, y, src.getPixel(sxR, syR));
      }
    }
  }

  return Uint8List.fromList(img.encodeJpg(dst, quality: _kDefaultJpegQuality));
}

List<double> _computeHomography({
  required List<Point2D> srcPts,
  required List<Point2D> dstPts,
}) {
  // Solve 8x8 linear system for h0..h7 (h8 fixed at 1).
  final A = List.generate(8, (_) => List<double>.filled(8, 0.0));
  final b = List<double>.filled(8, 0.0);

  for (int i = 0; i < 4; i++) {
    final sx = srcPts[i].x, sy = srcPts[i].y;
    final dx = dstPts[i].x, dy = dstPts[i].y;

    A[2 * i][0] = sx; A[2 * i][1] = sy; A[2 * i][2] = 1;
    A[2 * i][6] = -dx * sx; A[2 * i][7] = -dx * sy;
    b[2 * i] = dx;

    A[2 * i + 1][3] = sx; A[2 * i + 1][4] = sy; A[2 * i + 1][5] = 1;
    A[2 * i + 1][6] = -dy * sx; A[2 * i + 1][7] = -dy * sy;
    b[2 * i + 1] = dy;
  }

  final h = _gaussianElimination(A, b);
  return [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1.0];
}

List<double> _gaussianElimination(List<List<double>> A, List<double> b) {
  final n = b.length;
  final aug = List.generate(n, (i) => [...A[i], b[i]]);

  for (int col = 0; col < n; col++) {
    int maxRow = col;
    for (int row = col + 1; row < n; row++) {
      if (aug[row][col].abs() > aug[maxRow][col].abs()) maxRow = row;
    }
    final tmp = aug[col];
    aug[col] = aug[maxRow];
    aug[maxRow] = tmp;

    if (aug[col][col].abs() < 1e-10) {
      // Singular / degenerate system — co-linear corners produce no usable
      // homography. Surface the failure so the usecase can fall back instead
      // of silently producing a garbage warp.
      throw const ImageProcessingException('Degenerate homography matrix');
    }
    for (int row = col + 1; row < n; row++) {
      final f = aug[row][col] / aug[col][col];
      for (int j = col; j <= n; j++) {
        aug[row][j] -= f * aug[col][j];
      }
    }
  }

  final x = List<double>.filled(n, 0.0);
  for (int i = n - 1; i >= 0; i--) {
    x[i] = aug[i][n];
    for (int j = i + 1; j < n; j++) {
      x[i] -= aug[i][j] * x[j];
    }
    x[i] /= aug[i][i];
  }
  return x;
}
