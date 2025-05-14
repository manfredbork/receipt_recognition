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

  RecognizedPosition mostTrustworthyPosition({
    required RecognizedPosition compare,
    required int trustworthyThreshold,
    required RecognizedPosition Function() orElse,
  }) {
    final rank = <(String, String), int>{};

    for (final position in positions) {
      final product = position.product.value;
      final price = position.price.formattedValue;
      final key = (product, price);
      rank[key] = (rank[key] ?? 0) + 1;
    }

    final ranked =
        rank.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (ranked.isNotEmpty) {
      final topRank = ranked.first.key;
      final position = positions.firstWhere(
        (p) =>
            p.product.value == topRank.$1 &&
            p.price.formattedValue == topRank.$2 &&
            p.samePrice(compare),
        orElse: orElse,
      );

      final trustworthy = (ranked.first.value / positions.length * 100).toInt();

      if (trustworthy >= trustworthyThreshold) {
        return position;
      }
    }

    return orElse();
  }

  RecognizedPosition mostSimilarPosition({
    required RecognizedPosition compare,
    required int similarityThreshold,
    required RecognizedPosition Function() orElse,
  }) {
    final ranked =
        positions..sort(
          (a, b) => b.ratioProduct(compare).compareTo(a.ratioProduct(compare)),
        );

    final position = ranked.firstWhere(
      (p) => p.samePrice(compare),
      orElse: orElse,
    );

    return position;
  }
}
