import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a recognized price value (e.g. "2.99") extracted from a receipt line.
///
/// Inherits from [RecognizedEntity] and provides formatted numeric output.
final class RecognizedPrice extends RecognizedEntity<num> {
  /// Creates a [RecognizedPrice] from a [TextLine] and its parsed numeric value.
  RecognizedPrice({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
