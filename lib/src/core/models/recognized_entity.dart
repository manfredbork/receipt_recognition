import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents the type of update applied to a recognized receipt position.
enum Operation {
  /// A new position was added to the current state.
  added,

  /// An existing position was modified or replaced.
  updated,
}

/// A base class for value-carrying types with a formatted string output.
abstract class Valuable<T> {
  /// The raw, typed value.
  final T value;

  Valuable({required this.value});

  /// Converts the value into a human-readable string.
  String format(T value);

  /// The formatted version of the value.
  String get formattedValue => format(value);
}

/// A base class for OCR-recognized receipt entities derived from a [TextLine].
///
/// This includes both the original text line and its parsed value.
abstract class RecognizedEntity<T> extends Valuable<T> {
  /// The original line from OCR that this entity is based on.
  final TextLine line;

  RecognizedEntity({required this.line, required super.value});
}

/// Represents a recognized store/company name on a receipt.
final class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.line, required super.value});

  @override
  String format(String value) => value.toUpperCase();
}

/// Represents an unclassified text line on the receipt.
final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String format(String value) => value;
}

/// Represents a label near the total sum (e.g. "SUMME", "TOTAL").
final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.line, required super.value});

  @override
  String format(String value) => value;
}

/// Represents a detected amount (number) on the receipt line.
final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Represents the total sum detected on the receipt.
final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Represents the sum calculated from all recognized prices on the receipt.
///
/// This is a computed, not OCR-detected, value.
final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
