import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'position_group.dart';
import 'receipt_models.dart';

final class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;
  DateTime timestamp;
  PositionGroup group;
  Operation operation;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.group,
    required this.operation,
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
      group: group ?? this.group,
      operation: operation ?? this.operation,
    );
  }

  bool samePrice(RecognizedPosition other) {
    return price.formattedValue == other.price.formattedValue;
  }

  int ratioProduct(RecognizedPosition other) {
    return ratio(product.value, other.product.value);
  }

  int partialRatioProduct(RecognizedPosition other) {
    return partialRatio(product.value, other.product.value);
  }
}
