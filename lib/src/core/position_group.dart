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
    required trustworthyThreshold,
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
            p.price.formattedValue == topRank.$2,
        orElse: () => orElse(),
      );

      final trustworthy = (ranked.first.value / positions.length * 100).toInt();

      return trustworthy >= trustworthyThreshold ? position : orElse();
    }

    return orElse();
  }

  RecognizedPosition mostSimilarPosition(RecognizedPosition other) {
    return positions.reduce(
      (a, b) => a.similarity(other) > b.similarity(other) ? a : b,
    );
  }
}
