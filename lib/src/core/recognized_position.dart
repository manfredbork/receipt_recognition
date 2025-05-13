import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'position_group.dart';
import 'receipt_models.dart';

final class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;
  DateTime timestamp;
  int? trustworthiness;
  PositionGroup? group;
  Operation? operation;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    this.trustworthiness,
    this.group,
    this.operation,
  });

  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    int? trustworthiness,
    PositionGroup? group,
    Operation? operation,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      trustworthiness: trustworthiness ?? this.trustworthiness,
      group: group ?? this.group,
      operation: operation ?? this.operation,
    );
  }

  int similarity(RecognizedPosition other) {
    if (timestamp.isAtSameMomentAs(other.timestamp) ||
        price.formattedValue != other.price.formattedValue) {
      return 0;
    }
    return max(
      ratio(product.value, other.product.value),
      partialRatio(product.value, other.product.value),
    );
  }
}
