import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Unit price recognized from the receipt.
final class RecognizedUnitPrice extends RecognizedEntity<double> {
  /// Creates an unit price entity from [value] and [line].
  const RecognizedUnitPrice({required super.value, required super.line});

  @override
  String format(double value) => ReceiptFormatter.format(value);
}

/// Unit quantity recognized from the receipt.
final class RecognizedUnitQuantity extends RecognizedEntity<int> {
  /// Creates an unit quantity entity from [value] and [line].
  const RecognizedUnitQuantity({required super.value, required super.line});

  @override
  String format(int value) => value.toString();
}

/// Unit combine recognized price and quantity from the receipt.
final class RecognizedUnit {
  /// The unit quantity which belongs to product, if any.
  RecognizedUnitQuantity quantity;

  /// The unit price which belongs to product, if any.
  RecognizedUnitPrice price;

  /// Creates a recognized unit from [quantity] and [price].
  RecognizedUnit({required this.quantity, required this.price});

  /// Factory to create with [quantity] as int and [price] as double.
  factory RecognizedUnit.fromNumbers(
    int quantity,
    double price,
    TextLine line,
  ) => RecognizedUnit(
    quantity: RecognizedUnitQuantity(value: quantity, line: line),
    price: RecognizedUnitPrice(value: price, line: line),
  );
}
