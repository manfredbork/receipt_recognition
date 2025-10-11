import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models_public/recognized_base.dart';

/// Outer bounds and skew angle of the receipt.
final class RecognizedBoundingBox extends RecognizedEntity<Rect> {
  /// Creates a bounding box entity from [value] and [line].
  const RecognizedBoundingBox({required super.value, required super.line});

  /// Deskewed bounding box of the receipt.
  Rect get boundingBox => value;

  /// Original OCR bounding box before deskewing.
  Rect get deskewedBoundingBox => line.boundingBox;

  /// Estimated skew angle in degrees (if provided by OCR).
  double? get skewAngle => line.angle;

  @override
  String format(Rect value) => value.toString();
}

/// Bounding box boundaries across a set of text lines.
class RecognizedBounds {
  /// Minimum left coordinate.
  final double minLeft;

  /// Maximum right coordinate.
  final double maxRight;

  /// Creates bounds with [minLeft] and [maxRight].
  const RecognizedBounds({required this.minLeft, required this.maxRight});

  /// Canonical zero-bounds instance.
  static const RecognizedBounds zero = RecognizedBounds(
    minLeft: 0.0,
    maxRight: 0.0,
  );

  /// Creates bounds from [lines] by scanning for the minimum left
  /// and maximum right coordinates. Returns [zero] when [lines] is empty.
  static RecognizedBounds fromLines(List<TextLine> lines) {
    if (lines.isEmpty) return zero;

    var minLeft = double.infinity;
    var maxRight = double.negativeInfinity;

    for (final line in lines) {
      final box = line.boundingBox;
      final left = box.left.toDouble();
      final right = box.right.toDouble();
      if (left < minLeft) minLeft = left;
      if (right > maxRight) maxRight = right;
    }

    return RecognizedBounds(
      minLeft: minLeft.isFinite ? minLeft : 0.0,
      maxRight: maxRight.isFinite ? maxRight : 0.0,
    );
  }
}
