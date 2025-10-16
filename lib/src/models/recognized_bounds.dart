import 'dart:ui';

import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/utils/ocr/index.dart';

/// Outer bounds and skew angle of the receipt.
final class RecognizedBounds extends RecognizedEntity<Rect> {
  /// Creates a bounds entity from [value] and [line].
  const RecognizedBounds({required super.value, required super.line});

  /// Bounding box of the receipt.
  Rect get boundingBox => value;

  /// Estimated skew angle in degrees (if provided by OCR).
  double? get skewAngle => line.angle;

  /// Returns a copy with updated fields.
  RecognizedBounds copyWith({double? skewAngle}) {
    return RecognizedBounds(
      value: value,
      line: ReceiptTextLine(boundingBox: value, angle: skewAngle),
    );
  }

  @override
  String format(Rect value) => value.toString();
}
