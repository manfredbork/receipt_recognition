import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';
import 'package:receipt_recognition/src/utils/ocr/index.dart';

/// Price recognized from a receipt, with numeric value and confidence score.
final class RecognizedPrice extends RecognizedEntity<num> {
  /// Confidence assessment for this price recognition.
  Confidence? confidence;

  /// The position this price belongs to, if any.
  RecognizedPosition? position;

  /// Creates a recognized price from [value] and source [line].
  RecognizedPrice({
    required super.line,
    required super.value,
    this.confidence,
    this.position,
  });

  /// Creates a recognized price from JSON.
  factory RecognizedPrice.fromJson(Map<String, dynamic> json) {
    final rawValue = json['value'];
    final parsedValue =
        rawValue is num
            ? rawValue
            : num.tryParse(rawValue?.toString() ?? '0') ?? 0;
    final confValue =
        json['confidence'] is int
            ? json['confidence'] as int
            : int.tryParse(json['confidence']?.toString() ?? '0') ?? 0;

    return RecognizedPrice(
      value: parsedValue,
      confidence: Confidence(value: confValue),
      line: ReceiptTextLine(),
    );
  }

  /// Returns a copy with updated fields.
  RecognizedPrice copyWith({
    num? value,
    TextLine? line,
    Confidence? confidence,
    RecognizedPosition? position,
  }) {
    return RecognizedPrice(
      value: value ?? this.value,
      line: line ?? this.line,
      confidence: confidence ?? this.confidence,
      position: position ?? this.position,
    );
  }

  /// Formats the price value as a localized string.
  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Monetary amount recognized from the receipt.
final class RecognizedAmount extends RecognizedEntity<num> {
  /// Creates an amount entity from [value] and [line].
  const RecognizedAmount({required super.value, required super.line});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Total sum recognized from the receipt.
final class RecognizedSum extends RecognizedEntity<num> {
  /// Creates a sum entity from [value] and [line].
  const RecognizedSum({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedSum copyWith({num? value, TextLine? line}) =>
      RecognizedSum(value: value ?? this.value, line: line ?? this.line);

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Sum calculated from receipt positions rather than directly recognized.
final class CalculatedSum extends Valuable<num> {
  /// Creates a calculated sum from aggregated position values.
  const CalculatedSum({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Label for the sum/total (e.g., "Total", "Summe").
final class RecognizedSumLabel extends RecognizedEntity<String> {
  /// Creates a sum label entity from [value] and [line].
  const RecognizedSumLabel({required super.value, required super.line});

  @override
  String format(String value) => value;
}
