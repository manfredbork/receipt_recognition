import 'package:receipt_recognition/receipt_recognition.dart';

/// A group of similar [RecognizedPosition]s that represent the same
/// receipt line item detected across multiple scans.
///
/// Used to stabilize, filter, and rank OCR data using fuzzy matching
/// and frequency-based confidence.
final class PositionGroup {
  /// All positions associated with this group.
  final List<RecognizedPosition> positions;

  /// Creates a [PositionGroup] with a predefined list of positions.
  PositionGroup({required this.positions});

  /// Creates an empty position group.
  factory PositionGroup.empty() {
    return PositionGroup(positions: []);
  }

  /// Creates a group from a single [RecognizedPosition].
  ///
  /// This also sets its `positionIndex` to `0` to initialize ordering.
  factory PositionGroup.fromPosition(RecognizedPosition position) {
    position.positionIndex = 0;
    return PositionGroup(positions: [position]);
  }

  /// Returns a new [PositionGroup] with updated values.
  PositionGroup copyWith({List<RecognizedPosition>? positions}) {
    return PositionGroup(positions: positions ?? this.positions);
  }

  /// Calculates a map of (product, price) keys and their frequencies
  /// across the group, and returns the most common one.
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

  /// Returns the most frequently seen position in this group.
  ///
  /// Frequency is determined by the number of matching (product, price) pairs.
  RecognizedPosition mostTrustworthyPosition() {
    final topRank = bestTrustworthyRank();

    return positions.firstWhere(
      (p) =>
          p.product.value == topRank?.key.$1 &&
          p.price.formattedValue == topRank?.key.$2,
    );
  }

  /// Computes the trustworthiness of a position within this group
  /// based on how often the product value appears.
  int calculateTrustworthiness(RecognizedPosition position) {
    final count = positions.fold(
      0,
      (a, b) =>
          a +
          (b.product.formattedValue == position.product.formattedValue ? 1 : 0),
    );

    return (count / positions.length * 100).toInt();
  }

  /// Returns the position in this group that is most textually similar
  /// to [compare], based on fuzzy matching.
  RecognizedPosition mostSimilarPosition(RecognizedPosition compare) =>
      positions.reduce(
        (a, b) => a.ratioProduct(compare) > b.ratioProduct(compare) ? a : b,
      );

  /// Returns the trustworthiness score of the best candidate in this group.
  int get trustworthiness => mostTrustworthyPosition().trustworthiness;
}
