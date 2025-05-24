import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a product name or item label recognized from a receipt line.
///
/// Stores the original OCR line and its extracted value, with optional formatting.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Creates a [RecognizedProduct] from a [TextLine] and its string value.
  ///
  /// The [formattedValue] defaults to the raw [value].
  RecognizedProduct({required super.line, required super.value});

  /// Creates a copy of this product with optional modifications.
  RecognizedProduct copyWith({String? value, TextLine? line}) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => ReceiptFormatter.normalize(value);
}
