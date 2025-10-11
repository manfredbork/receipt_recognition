import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Purchase date recognized from a receipt.
final class RecognizedPurchaseDate extends RecognizedEntity<String> {
  /// Creates a purchase date entity from [value] and [line].
  const RecognizedPurchaseDate({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedPurchaseDate copyWith({String? value, TextLine? line}) =>
      RecognizedPurchaseDate(
        value: value ?? this.value,
        line: line ?? this.line,
      );

  /// Parsed [DateTime] if possible.
  DateTime? get parsedDateTime => ReceiptFormatter.parseDate(value);

  @override
  String format(String value) => value;
}
