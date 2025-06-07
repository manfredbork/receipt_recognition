import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a line item position on a receipt, consisting of a product and its price.
///
/// Each position corresponds to a single item purchased in the transaction.
final class RecognizedPosition {
  /// The product part of this position (name/description).
  final RecognizedProduct product;

  /// The price part of this position.
  final RecognizedPrice price;

  /// Timestamp when this position was recognized.
  DateTime timestamp;

  /// The operation performed on this position (added, updated, etc.).
  Operation operation;

  /// Optional group this position belongs to for optimization purposes.
  RecognizedGroup? group;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.operation,
    this.group,
  });

  /// Creates a [RecognizedPosition] from a JSON map.
  factory RecognizedPosition.fromJson(Map<String, dynamic> json) {
    return RecognizedPosition(
      product: RecognizedProduct.fromJson(json['product']),
      price: RecognizedPrice.fromJson(json['price']),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
      operation: Operation.none,
    );
  }

  /// Creates a copy of this position with optionally updated properties.
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

  /// Gets the overall confidence score for this position.
  ///
  /// Calculated as the average of product and price confidence scores.
  int get confidence {
    final avg = (product.confidence + price.confidence) / 2;
    return avg.isFinite ? avg.toInt() : 0;
  }
}
