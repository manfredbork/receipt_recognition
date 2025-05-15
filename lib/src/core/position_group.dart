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

  int calculateTrustworthiness(
    RecognizedPosition compare, {
    sameProduct = true,
    samePrice = true,
  }) {
    final topRank = bestTrustworthyRank(
      compare,
      sameProduct: sameProduct,
      samePrice: samePrice,
    );

    if (topRank == null) return 0;

    return (topRank.value / positions.length * 100).toInt();
  }

  MapEntry<(String, String), int>? bestTrustworthyRank(
    RecognizedPosition compare, {
    sameProduct = false,
    samePrice = true,
  }) {
    final rank = <(String, String), int>{};

    for (final position in positions) {
      final product = position.product.value;
      final price = position.price.formattedValue;
      final key = (product, price);
      rank[key] = (rank[key] ?? 0) + 1;
    }

    final ranked =
        rank.entries.toList()..sort((a, b) => a.value.compareTo(b.value));

    if (ranked.isNotEmpty) {
      final lastIndex = ranked.lastIndexWhere(
        (r) =>
            (sameProduct ? compare.product.formattedValue == r.key.$1 : true) &&
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
    sameProduct = false,
    samePrice = true,
  }) {
    final topRank = bestTrustworthyRank(
      compare,
      sameProduct: sameProduct,
      samePrice: samePrice,
    );

    if (topRank == null) return compare;

    return positions.firstWhere(
      (p) =>
          p.product.value == topRank.key.$1 &&
          p.price.formattedValue == topRank.key.$2,
      orElse: () => compare,
    );
  }

  RecognizedPosition mostSimilarPosition(RecognizedPosition compare) {
    final ranked = List<RecognizedPosition>.from(positions)..sort((a, b) {
      if (a.timestamp.isAtSameMomentAs(b.timestamp)) {
        return a.sameTimestamp(compare).compareTo(b.sameTimestamp(compare));
      } else if (a.ratioProduct(compare) == b.ratioProduct(compare)) {
        return a.samePrice(compare).compareTo(b.samePrice(compare));
      }
      return a.ratioProduct(compare).compareTo(b.ratioProduct(compare));
    });

    return ranked.last;
  }
}
