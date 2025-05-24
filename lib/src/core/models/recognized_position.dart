import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a single recognized item (product and price) on a receipt,
/// along with metadata about its grouping and scan context.
final class RecognizedPosition {
  /// The recognized product name from OCR.
  final RecognizedProduct product;

  /// The recognized price for this product.
  final RecognizedPrice price;

  /// Timestamp of when this position was recorded.
  DateTime timestamp;

  /// Indicates whether the position was added, updated, or unchanged.
  Operation operation;

  /// Index representing the scanned frame index.
  int scanIndex = 0;

  /// Creates a [RecognizedPosition] with all required attributes.
  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.operation,
    required this.scanIndex,
  });

  /// Creates a modified copy of this position.
  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    Operation? operation,
    int? scanIndex,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      operation: operation ?? this.operation,
      scanIndex: scanIndex ?? this.scanIndex,
    );
  }
}
