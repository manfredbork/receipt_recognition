import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a product name recognized from a receipt.
///
/// Contains the product description and methods to normalize and format it.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Confidence score for this recognition (0-100).
  int confidence;

  /// The position this product belongs to, if any.
  RecognizedPosition? position;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.confidence = 0,
    this.position,
  });

  /// Creates a copy of this product with optionally updated properties.
  RecognizedProduct copyWith({
    String? value,
    TextLine? line,
    int? confidence,
    RecognizedPosition? position,
  }) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
      confidence: confidence ?? this.confidence,
      position: position ?? this.position,
    );
  }

  /// Formats the product name by trimming excess whitespace.
  @override
  String format(String value) => ReceiptFormatter.trim(value);

  /// Gets the formatted product text.
  String get text => formattedValue;

  /// Gets a normalized version of the product name.
  ///
  /// Uses alternative texts from the group to improve naming consistency.
  String get normalizedText =>
      ReceiptNormalizer.normalizeByAlternativeTexts(alternativeTexts) ?? text;

  /// Gets alternative text variations of this product from its group.
  List<String> get alternativeTexts => position?.group?.alternativeTexts ?? [];
}
