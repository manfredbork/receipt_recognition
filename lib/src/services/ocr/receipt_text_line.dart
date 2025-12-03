import 'dart:math';
import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Internal synthetic [TextLine] used by the parser/optimizer to create
/// deskewed/generated lines without invoking OCR again. Not exported publicly.
class ReceiptTextLine implements TextLine {
  /// Full text content of the synthetic line.
  @override
  final String text;

  /// Token-level elements that compose this line (often empty for synthetic lines).
  @override
  final List<TextElement> elements;

  /// Bounding box of the line in image coordinates.
  @override
  final Rect boundingBox;

  /// Languages associated with this line (usually empty for synthetic lines).
  @override
  final List<String> recognizedLanguages;

  /// Corner points of the line’s quadrilateral (may be empty for synthetic lines).
  @override
  final List<Point<int>> cornerPoints;

  /// OCR confidence if available (typically `null` for synthetic lines).
  @override
  final double? confidence;

  /// Skew angle in degrees if known.
  @override
  final double? angle;

  /// Creates a synthetic line with optional text, geometry and metadata.
  const ReceiptTextLine({
    this.text = '',
    this.elements = const [],
    this.boundingBox = Rect.zero,
    this.recognizedLanguages = const [],
    this.cornerPoints = const [],
    this.confidence,
    this.angle,
  });

  /// Convenience constructor to build a synthetic line from [TextLine] line.
  factory ReceiptTextLine.fromLine(TextLine line) => ReceiptTextLine(
    text: line.text,
    elements: line.elements,
    boundingBox: line.boundingBox,
    recognizedLanguages: line.recognizedLanguages,
    cornerPoints: line.cornerPoints,
    confidence: line.confidence,
    angle: line.angle,
  );

  /// Returns a copy with updated fields.
  ReceiptTextLine copyWith({
    String? text,
    List<TextElement>? elements,
    Rect? boundingBox,
    List<String>? recognizedLanguages,
    List<Point<int>>? cornerPoints,
    double? confidence,
    double? angle,
  }) {
    return ReceiptTextLine(
      text: text ?? this.text,
      elements: elements ?? this.elements,
      boundingBox: boundingBox ?? this.boundingBox,
      recognizedLanguages: recognizedLanguages ?? this.recognizedLanguages,
      cornerPoints: cornerPoints ?? this.cornerPoints,
      confidence: confidence ?? this.confidence,
      angle: angle ?? this.angle,
    );
  }
}
