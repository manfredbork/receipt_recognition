import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

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

/// Total recognized from the receipt.
final class RecognizedTotal extends RecognizedEntity<num> {
  /// Creates a total entity from [value] and [line].
  const RecognizedTotal({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedTotal copyWith({num? value, TextLine? line}) =>
      RecognizedTotal(value: value ?? this.value, line: line ?? this.line);

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Sum recognized from a receipt.
final class RecognizedSum extends RecognizedTotal {
  /// Creates a sum entity from [value] and [line].
  const RecognizedSum({required super.value, required super.line});
}

/// Total calculated from receipt positions rather than directly recognized.
final class CalculatedTotal extends Valuable<num> {
  /// Creates a calculated total from aggregated position values.
  const CalculatedTotal({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Sum calculated from receipt positions rather than directly recognized.
final class CalculatedSum extends CalculatedTotal {
  /// Creates a calculated sum from aggregated position values.
  const CalculatedSum({required super.value});
}

/// Label for the total (e.g., "Total", "Summe").
final class RecognizedTotalLabel extends RecognizedEntity<String> {
  /// Creates a total label entity from [value] and [line].
  const RecognizedTotalLabel({required super.value, required super.line});

  /// Returns a copy with updated fields.
  RecognizedTotalLabel copyWith({String? value, TextLine? line}) =>
      RecognizedTotalLabel(value: value ?? this.value, line: line ?? this.line);

  @override
  String format(String value) => value;
}

/// Label for the sum (e.g., "Total", "Summe").
final class RecognizedSumLabel extends RecognizedTotalLabel {
  /// Creates a sum label entity from [value] and [line].
  const RecognizedSumLabel({required super.value, required super.line});
}
