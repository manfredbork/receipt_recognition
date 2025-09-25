import 'dart:math' as math;

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
      final prodRect = pos.product.line.boundingBox;
      final priceRect = pos.price.line.boundingBox;

      leftPoints.add(
        _WPoint(
          x: prodRect.left.toDouble(),
          y: prodRect.center.dy,
          w: pos.confidence.toDouble().clamp(1, 100),
        ),
      );

      rightPoints.add(
        _WPoint(
          x: priceRect.right.toDouble(),
          y: priceRect.center.dy,
          w: pos.confidence.toDouble().clamp(1, 100),
        ),
      );
    }

    final leftDeg = _fitAngleDegrees(leftPoints, minSamples);
    final rightDeg = _fitAngleDegrees(rightPoints, minSamples);

    if (leftDeg != null && rightDeg != null) {
      return (leftDeg + rightDeg) / 2.0;
    } else if (leftDeg != null) {
      return leftDeg;
    } else if (rightDeg != null) {
      return rightDeg;
    }
    return 0.0;
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
