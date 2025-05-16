import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'recognized_position.dart';

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required this.positions});

  factory PositionGroup.empty() {
    return PositionGroup(positions: []);
  }

  factory PositionGroup.fromPosition(RecognizedPosition position) {
    return PositionGroup(positions: [position]);
  }

  MapEntry<(String, String), int>? bestTrustworthyRank(
    RecognizedPosition compare, {
    similarProduct = false,
    samePrice = true,
    similarityThreshold = 50,
  }) {
    final rank = <(String, String), int>{};

    for (final position in positions) {
      final product = similarProduct ? position.product.value : '';
      final price = samePrice ? position.price.formattedValue : '';
      final key = (product, price);
      rank[key] = (rank[key] ?? 0) + 1;
    }

    final ranked =
        rank.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    if (ranked.isNotEmpty) {
      final lastIndex = ranked.lastIndexWhere(
        (r) =>
            (similarProduct
                ? ratio(compare.product.formattedValue, r.key.$1) >=
                    similarityThreshold
                : true) &&
            (samePrice ? compare.price.formattedValue == r.key.$2 : true),
      );
      if (lastIndex < 0) {
        return null;
      }
      return ranked[lastIndex];
    }

    return null;
  }

  RecognizedPosition mostTrustworthyPosition(
    RecognizedPosition compare, {
    similarProduct = false,
    samePrice = true,
    similarityThreshold = 50,
  }) {
    final topRank = bestTrustworthyRank(
      compare,
      similarProduct: similarProduct,
      samePrice: samePrice,
      similarityThreshold: similarityThreshold,
    );

    if (topRank == null) return compare;

    return positions.firstWhere(
      (p) => (samePrice ? p.price.formattedValue == topRank.key.$2 : true),
      orElse: () => compare,
    );
  }

  RecognizedPosition mostSimilarPosition(RecognizedPosition compare) {
    final ranked = List<RecognizedPosition>.from(positions)..sort((a, b) {
      final compareTo = a
          .ratioProduct(compare)
          .compareTo(b.ratioProduct(compare));

      if (compareTo == 0) {
        return a.samePrice(compare).compareTo(b.samePrice(compare));
      }

      return compareTo;
    });

    return ranked.last;
  }
}
