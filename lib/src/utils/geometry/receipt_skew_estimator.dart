import 'dart:math' as math;

import 'package:receipt_recognition/src/models/index.dart';

/// Estimates the skew angle (degrees) of a receipt from its product/price columns.
/// Positive angle means the receipt drifts to the right as Y increases (clockwise tilt).
class ReceiptSkewEstimator {
  /// Estimates skew in degrees using weighted linear fits of left/right columns.
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
      if ((leftDeg - rightDeg).abs() > 2.0) {
        resultDeg = math.min(leftDeg, rightDeg);
      } else {
        resultDeg = (leftDeg + rightDeg) / 2.0;
      }
    } else if (leftDeg != null) {
      resultDeg = leftDeg;
    } else if (rightDeg != null) {
      resultDeg = rightDeg;
    } else {
      resultDeg = 0.0;
    }
    return resultDeg.abs() < 0.5 ? 0.0 : resultDeg;
  }

  /// Fits a weighted line and returns its angle in degrees, or null if insufficient data.
  static double? _fitAngleDegrees(List<_WPoint> pts, int minSamples) {
    if (pts.length < minSamples) return null;
    final fit = _fitSlope(pts);
    if (fit == null) return null;
    return math.atan(fit.a) * 180.0 / math.pi;
  }

  /// Computes weighted least-squares slope/intercept for x = a*y + b.
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

/// Weighted sample point used for the skew fit (x, y, with weight w).
class _WPoint {
  final double x;
  final double y;
  final double w;

  _WPoint({required this.x, required this.y, required this.w});
}

/// Weighted least-squares line parameters for x = a*y + b.
class _LineFit {
  final double a;
  final double b;

  _LineFit({required this.a, required this.b});
}
