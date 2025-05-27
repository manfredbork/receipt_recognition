import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;

  DateTime timestamp;
  Operation operation;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.operation,
  });

  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    Operation? operation,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      operation: operation ?? this.operation,
    );
  }
}
