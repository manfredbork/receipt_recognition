import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;
  DateTime timestamp;
  PositionGroup group;
  Operation operation;
  int positionIndex = 0;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.group,
    required this.operation,
    required this.positionIndex,
  });

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

  int ratioProduct(RecognizedPosition other) {
    return max(
      ratio(product.value, other.product.value),
      partialRatio(product.value, other.product.value),
    );
  }

  int get trustworthiness => group.calculateTrustworthiness(this);
}
