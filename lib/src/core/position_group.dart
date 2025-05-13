import 'recognized_position.dart';

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required RecognizedPosition position})
    : positions = [position];

  DateTime youngestTimestamp() {
    return positions
        .reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b)
        .timestamp;
  }

  RecognizedPosition mostTrustworthy(RecognizedPosition defaultPosition) {
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
            p.price.formattedValue == defaultPosition.price.formattedValue,
        orElse: () => defaultPosition,
      );

      position.trustworthiness =
          (ranked.first.value / positions.length * 100).toInt();
      return position;
    }

    return defaultPosition;
  }

  RecognizedPosition mostSimilar(RecognizedPosition position) {
    return positions.reduce(
      (a, b) => a.similarity(position) > b.similarity(position) ? a : b,
    );
  }
}
