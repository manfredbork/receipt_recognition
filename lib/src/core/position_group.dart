import 'recognized_position.dart';

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required position}) : positions = [position];

  DateTime oldestTimestamp() {
    return positions
        .reduce(
          (a, b) =>
              a.timestamp.millisecondsSinceEpoch <
                      b.timestamp.millisecondsSinceEpoch
                  ? a
                  : b,
        )
        .timestamp;
  }

  RecognizedPosition? mostTrustworthy({
    RecognizedPosition? defaultPosition,
    priceRequired = false,
  }) {
    final Map<(String, String), int> rank = {};

    for (final position in positions) {
      final product = position.product.value;
      final price = position.price.formattedValue;
      final key = (product, price);

      if (rank.containsKey(key)) {
        rank[key] = rank[key]! + 1;
      } else {
        rank[key] = 1;
      }
    }

    final ranked = List<MapEntry<(String, String), int>>.from(rank.entries)
      ..sort((a, b) => a.value.compareTo(b.value));

    if (ranked.isNotEmpty) {
      final position = positions.firstWhere(
        (p) =>
            ranked.last.key.$1 == p.product.value &&
            ranked.last.key.$2 == p.price.formattedValue &&
            ranked.last.key.$2 ==
                (defaultPosition != null && priceRequired
                    ? defaultPosition.price.formattedValue
                    : ranked.last.key.$2),
      );

      position.trustworthiness =
          (ranked.last.value / positions.length * 100).toInt();

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
