import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Unit price recognized from the receipt.
final class RecognizedUnitPrice extends RecognizedEntity<num> {
  /// Creates an unit price entity from [value] and [line].
  const RecognizedUnitPrice({required super.value, required super.line});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

/// Unit quantity recognized from the receipt.
final class RecognizedUnitQuantity extends RecognizedEntity<num> {
  /// Creates an unit quantity entity from [value] and [line].
  const RecognizedUnitQuantity({required super.value, required super.line});

  @override
  String format(num value) => ReceiptFormatter.format(value, decimalDigits: 0);
}
