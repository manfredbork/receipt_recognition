import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Base class for entities that have a value which can be formatted.
abstract class Valuable<T> {
  /// Underlying value.
  final T value;

  /// Creates a valuable with the given [value].
  const Valuable({required this.value});

  /// Formats [value] into a string representation.
  String format(T value);

  /// Formatted string representation of [value].
  String get formattedValue => format(value);
}

/// Base class for entities recognized from a receipt through OCR.
abstract class RecognizedEntity<T> extends Valuable<T> {
  /// Source text line recognized by OCR.
  final TextLine line;

  /// Creates a recognized entity from [line] and [value].
  const RecognizedEntity({required super.value, required this.line});
}

/// Unidentified text line from the receipt.
final class RecognizedUnknown extends RecognizedEntity<String> {
  /// Creates an unknown entity from [value] and [line].
  const RecognizedUnknown({required super.value, required super.line});

  @override
  String format(String value) => value;
}

/// Operation performed on a recognized position during processing.
enum Operation {
  /// No change.
  none,

  /// Newly added.
  added,

  /// Updated from a previous state.
  updated,
}

/// Weighted confidence score used to evaluate recognition reliability.
final class Confidence extends Valuable<int> {
  /// Relative influence of this confidence value when aggregated with others.
  int weight;

  /// Creates a confidence from numeric [value] and optional [weight].
  Confidence({required super.value, this.weight = 1});

  @override
  String format(int value) => '$value%';
}
