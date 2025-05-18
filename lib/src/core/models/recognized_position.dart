import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
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

  /// The group this position belongs to for consolidation.
  PositionGroup group;

  /// Indicates whether the position was added, updated, or unchanged.
  Operation operation;

  /// Index representing the position’s order within the scanned frame.
  int positionIndex = 0;

  /// Creates a [RecognizedPosition] with all required attributes.
  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.group,
    required this.operation,
    required this.positionIndex,
  });

  /// Creates a modified copy of this position.
  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    PositionGroup? group,
    Operation? operation,
    int? positionIndex,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      group: group ?? this.group,
      operation: operation ?? this.operation,
      positionIndex: positionIndex ?? this.positionIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecognizedPosition &&
          runtimeType == other.runtimeType &&
          product.value == other.product.value &&
          price.value == other.price.value &&
          timestamp == other.timestamp;

  @override
  int get hashCode => Object.hash(product.value, price.value, timestamp);

  /// Calculates the fuzzy string similarity between this product name
  /// and another [RecognizedPosition]'s name.
  ///
  /// Uses both full and partial match ratios and returns the max value.
  int ratioProduct(RecognizedPosition other) {
    return max(
      ratio(product.value, other.product.value),
      partialRatio(product.value, other.product.value),
    );
  }

  /// Returns how trustworthy this position is within its group,
  /// expressed as a percentage from 0 to 100.
  int get trustworthiness => group.calculateTrustworthiness(this);
}
