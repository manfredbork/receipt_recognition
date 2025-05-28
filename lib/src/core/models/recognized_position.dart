import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;

  DateTime timestamp;
  Operation operation;
  RecognizedGroup? group;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.operation,
    this.group,
  });

  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    Operation? operation,
    RecognizedGroup? group,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      operation: operation ?? this.operation,
      group: group ?? this.group,
    );
  }

  int get confidence => ((product.confidence + price.confidence) / 2).toInt();
}
