import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a price recognized from a receipt.
///
/// Contains the numeric price value and its confidence score.
final class RecognizedPrice extends RecognizedEntity<num> {
  /// Confidence score for this recognition (0-100).
  int confidence;

  /// The position this price belongs to, if any.
  RecognizedPosition? position;

  RecognizedPrice({
    required super.line,
    required super.value,
    this.confidence = 0,
    this.position,
  });

  /// Creates a copy of this price with optionally updated properties.
  RecognizedPrice copyWith({
    num? value,
    TextLine? line,
    int? confidence,
    RecognizedPosition? position,
  }) {
    return RecognizedPrice(
      value: value ?? this.value,
      line: line ?? this.line,
      confidence: confidence ?? this.confidence,
      position: position ?? this.position,
    );
  }

  /// Formats the price value using the ReceiptFormatter.
  @override
  String format(num value) => ReceiptFormatter.format(value);
}
