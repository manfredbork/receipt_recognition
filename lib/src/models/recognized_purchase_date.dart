import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';

/// Purchase date recognized from a receipt.
///
/// The `value` is a parsed `DateTime`. Prefer storing UTC to avoid
/// timezone ambiguity; formatting uses ISO-8601 via `toIso8601String()`.
final class RecognizedPurchaseDate extends RecognizedEntity<DateTime> {
  /// Creates a purchase date entity from a parsed [value] and its source [line].
  const RecognizedPurchaseDate({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedPurchaseDate copyWith({DateTime? value, TextLine? line}) =>
      RecognizedPurchaseDate(
        value: value ?? this.value,
        line: line ?? this.line,
      );

  /// The parsed `DateTime` value.
  DateTime? get parsedDateTime => value;

  /// Formats the date as ISO-8601 using `DateTime.toIso8601String()`.
  ///
  /// For UTC values, this yields strings like `2025-10-16T09:15:30.123Z`.
  /// For local (non-UTC) values, this yields strings like
  /// `2025-10-16T11:15:30.123` without a timezone designator.
  @override
  String format(DateTime value) => value.toIso8601String();
}
