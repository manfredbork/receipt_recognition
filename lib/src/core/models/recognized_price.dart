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

  /// Formats the price value using the ReceiptFormatter.
  @override
  String format(num value) => ReceiptFormatter.format(value);
}
