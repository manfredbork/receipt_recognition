import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Estimates the skew angle (degrees) of a receipt from its product/price columns.
/// Positive angle means the receipt drifts to the right as Y increases (clockwise tilt).
class ReceiptSkewEstimator {
  static double estimateDegrees(
    RecognizedReceipt receipt, {
    int minSamples = 3,
  }) {
    final leftPoints = <_WPoint>[];
    final rightPoints = <_WPoint>[];

    for (final pos in receipt.positions) {
      final prodPts = pos.product.line.cornerPoints;
      final pricePts = pos.price.line.cornerPoints;

      if (prodPts.length >= 4) {
        leftPoints.add(
          _WPoint(
            x: prodPts.first.x.toDouble(),
            y: prodPts.first.y.toDouble(),
            w: pos.confidence.toDouble().clamp(1, 100),
          ),
        );
      }

      if (pricePts.length >= 4) {
        rightPoints.add(
          _WPoint(
            x: pricePts[3].x.toDouble(),
            y: pricePts[3].y.toDouble(),
            w: pos.confidence.toDouble().clamp(1, 100),
          ),
        );
      }
    }

    final leftDeg = _fitAngleDegrees(leftPoints, minSamples);
    final rightDeg = _fitAngleDegrees(rightPoints, minSamples);
    final double resultDeg;

    if (leftDeg != null && rightDeg != null) {
      resultDeg = (leftDeg + rightDeg) / 2.0;
    } else if (leftDeg != null) {
      resultDeg = leftDeg;
    } else if (rightDeg != null) {
      resultDeg = rightDeg;
    } else {
      resultDeg = 0.0;
    }
    return resultDeg.abs() < 0.5 ? 0.0 : resultDeg;
  }

  /// Weighted least squares fit of x = a*y + b, then angle = atan(a) in degrees.
  static double? _fitAngleDegrees(List<_WPoint> pts, int minSamples) {
    if (pts.length < minSamples) return null;
    final fit = _fitSlope(pts);
    if (fit == null) return null;
    return math.atan(fit.a) * 180.0 / math.pi;
  }

  static _LineFit? _fitSlope(List<_WPoint> pts) {
    double sw = 0, sy = 0, sx = 0;
    for (final p in pts) {
      sw += p.w;
      sy += p.w * p.y;
      sx += p.w * p.x;
    }
    if (sw == 0) return null;

    final yBar = sy / sw;
    final xBar = sx / sw;

    double num = 0, den = 0;
    for (final p in pts) {
      final w = p.w;
      final dy = p.y - yBar;
      num += w * dy * (p.x - xBar);
      den += w * dy * dy;
    }
    if (den == 0) return _LineFit(a: 0, b: xBar);

    final a = num / den;
    final b = xBar - a * yBar;
    return _LineFit(a: a, b: b);
  }
}

class _WPoint {
  final double x;
  final double y;
  final double w;

  _WPoint({required this.x, required this.y, required this.w});
}

class _LineFit {
  final double a;
  final double b;

  _LineFit({required this.a, required this.b});
}

extension on Rect {
  double get centerY => (top + bottom) / 2.0;
}

/// Estimates the skew angle (degrees) from raw OCR lines (no positions needed).
/// Strategy:
/// - For each line, take a representative point on the **left edge** and one on
///   the **right edge** (prefer cornerPoints; fall back to boundingBox).
/// - Fit x = a*y + b (weighted) for left and right sets separately.
/// - Angle = atan(a) in degrees; return the average of left & right when both available.
extension ReceiptSkewEstimatorFromLines on ReceiptSkewEstimator {
  static double estimateDegreesFromLines(
    List<TextLine> lines, {
    int minSamples = 6,
  }) {
    final left = <_WPoint>[];
    final right = <_WPoint>[];

    for (final line in lines) {
      if (line.cornerPoints.length >= 4) {
        // ML Kit ordering is usually top-left, top-right, bottom-right, bottom-left
        // but we guard by selecting minX and maxX points to be safe.
        final pts =
            line.cornerPoints
                .map((p) => math.Point<double>(p.x.toDouble(), p.y.toDouble()))
                .toList();

        final leftMost = pts.reduce((a, b) => (a.x < b.x) ? a : b);
        final rightMost = pts.reduce((a, b) => (a.x > b.x) ? a : b);
        final wy = _safeWeight(line);
        left.add(_WPoint(x: leftMost.x, y: leftMost.y, w: wy));
        right.add(_WPoint(x: rightMost.x, y: rightMost.y, w: wy));
      } else {
        final bb = line.boundingBox;
        final wy = _safeWeight(line);
        // Use the box edges at the vertical center as representative points
        left.add(_WPoint(x: bb.left.toDouble(), y: bb.centerY, w: wy));
        right.add(_WPoint(x: bb.right.toDouble(), y: bb.centerY, w: wy));
      }
    }

    final leftDeg = ReceiptSkewEstimator._fitAngleDegrees(left, minSamples);
    final rightDeg = ReceiptSkewEstimator._fitAngleDegrees(right, minSamples);
    final double resultDeg;

    if (leftDeg != null && rightDeg != null) {
      resultDeg = (leftDeg + rightDeg) / 2.0;
    } else if (leftDeg != null) {
      resultDeg = leftDeg;
    } else if (rightDeg != null) {
      resultDeg = rightDeg;
    } else {
      resultDeg = 0.0;
    }
    return resultDeg.abs() < 0.5 ? 0.0 : resultDeg;
  }
}

// Helper: turn TextLine confidence/geometry into a sane weight (1..100).
double _safeWeight(TextLine line) {
  final c = (line.confidence ?? 50).toDouble();
  // As a tiny stabilizer, blend in line height (clipped) so taller lines carry a bit more weight.
  final h = (line.boundingBox.height.toDouble()).clamp(8.0, 80.0);
  final blended = 0.85 * c + 0.15 * (h * 100.0 / 80.0);
  return blended.clamp(1.0, 100.0);
}
