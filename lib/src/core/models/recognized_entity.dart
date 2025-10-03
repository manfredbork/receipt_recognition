import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents the operation performed on a recognized position during processing.
enum Operation {
  /// No change applied to the position.
  none,

  /// Position was newly added.
  added,

  /// Position was updated from a previous state.
  updated,
}

/// Base class for entities that have a value which can be formatted.
///
/// Provides a common interface for getting formatted representation of values.
abstract class Valuable<T> {
  /// The underlying value of this entity.
  final T value;

  /// Creates a valuable entity with the given [value].
  Valuable({required this.value});

  /// Formats the underlying value into a string representation.
  String format(T value);

  /// Gets the formatted string representation of the value.
  String get formattedValue => format(value);
}

/// Base class for entities recognized from a receipt through OCR.
///
/// Associates a value with its source text line from the OCR process.
abstract class RecognizedEntity<T> extends Valuable<T> {
  /// The text line from which this entity was recognized.
  final TextLine line;

  /// Creates a recognized entity from a [line] and its [value].
  RecognizedEntity({required super.value, required this.line});
}

/// Represents a recognized company or store name from a receipt.
final class RecognizedCompany extends RecognizedEntity<String> {
  /// Creates a company entity from [value] and source [line].
  RecognizedCompany({required super.value, required super.line});

  /// Creates a copy of this company with optionally updated properties.
  RecognizedCompany copyWith({String? value, TextLine? line}) {
    return RecognizedCompany(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => value.toUpperCase();
}

/// Represents an unidentified text line from the receipt.
final class RecognizedUnknown extends RecognizedEntity<String> {
  /// Creates an unknown entity from [value] and source [line].
  RecognizedUnknown({required super.value, required super.line});

  @override
  String format(String value) => value;
}

/// Represents the outer bounds and the skew angle of the receipt.
final class RecognizedBoundingBox extends RecognizedEntity<Rect> {
  /// Creates a bounding box entity from [value] and source [line].
  RecognizedBoundingBox({required super.value, required super.line});

  /// The deskewed bounding box of the receipt.
  Rect get boundingBox => value;

  /// The original OCR bounding box before deskewing.
  Rect get deskewedBoundingBox => line.boundingBox;

  /// The estimated skew angle in degrees, if provided by OCR.
  double? get skewAngle => line.angle;

  @override
  String format(Rect value) => value.toString();
}

/// Represents a label for the sum/total (e.g., "Total", "Summe", etc.)
final class RecognizedSumLabel extends RecognizedEntity<String> {
  /// Creates a sum label entity from [value] and source [line].
  RecognizedSumLabel({required super.value, required super.line});

  @override
  String format(String value) => value;
}

/// Represents a monetary amount recognized from the receipt.
final class RecognizedAmount extends RecognizedEntity<num> {
  /// Creates an amount entity from [value] and source [line].
  RecognizedAmount({required super.value, required super.line});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Represents the total sum recognized from the receipt.
final class RecognizedSum extends RecognizedEntity<num> {
  /// Creates a sum entity from [value] and source [line].
  RecognizedSum({required super.value, required super.line});

  /// Creates a copy of this sum with optionally updated properties.
  RecognizedSum copyWith({num? value, TextLine? line}) {
    return RecognizedSum(value: value ?? this.value, line: line ?? this.line);
  }

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Represents a sum calculated from receipt positions rather than directly recognized.
final class CalculatedSum extends Valuable<num> {
  /// Creates a calculated sum from aggregated position values.
  CalculatedSum({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
