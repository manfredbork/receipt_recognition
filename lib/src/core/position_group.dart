import 'package:receipt_recognition/receipt_recognition.dart';

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required this.positions});

  factory PositionGroup.empty() {
    return PositionGroup(positions: []);
  }

  factory PositionGroup.fromPosition(RecognizedPosition position) {
    position.positionIndex = 0;
    return PositionGroup(positions: [position]);
  }

  PositionGroup copyWith({
    List<RecognizedPosition>? positions,
    RecognizedProduct? frozenProduct,
    RecognizedPrice? frozenPrice,
  }) {
    return PositionGroup(positions: positions ?? this.positions);
  }

  MapEntry<(String, String), int>? bestTrustworthyRank() {
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
      return ranked.last;
    }

    return null;
  }

  RecognizedPosition mostTrustworthyPosition() {
    final topRank = bestTrustworthyRank();

    return positions.firstWhere(
      (p) =>
          p.product.value == topRank?.key.$1 &&
          p.price.formattedValue == topRank?.key.$2,
    );
  }

  int calculateTrustworthiness(RecognizedPosition position) {
    final count = positions.fold(
      0,
      (a, b) =>
          a +
          (b.product.formattedValue == position.product.formattedValue ? 1 : 0),
    );

    return (count / positions.length * 100).toInt();
  }

  RecognizedPosition mostSimilarPosition(RecognizedPosition compare) =>
      positions.reduce(
        (a, b) => a.ratioProduct(compare) > b.ratioProduct(compare) ? a : b,
      );

  int get trustworthiness => mostTrustworthyPosition().trustworthiness;
}
