import 'position_group.dart';
import 'receipt_models.dart';
import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class CachedReceipt extends RecognizedReceipt {
  List<PositionGroup> positionGroups;
  int similarityThreshold;
  int trustworthyThreshold;
  int maxCacheSize;

  CachedReceipt({
    required super.positions,
    required super.timestamp,
    required super.videoFeed,
    required this.positionGroups,
    this.similarityThreshold = 75,
    this.trustworthyThreshold = 50,
    this.maxCacheSize = 10,
    super.sumLabel,
    super.sum,
    super.company,
  });

  @override
  CachedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    bool? videoFeed,
    List<PositionGroup>? positionGroups,
    int? similarityThreshold,
    int? trustworthyThreshold,
    int? maxCacheSize,
    RecognizedSumLabel? sumLabel,
    RecognizedSum? sum,
    RecognizedCompany? company,
  }) {
    return CachedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      videoFeed: videoFeed ?? this.videoFeed,
      positionGroups: positionGroups ?? this.positionGroups,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      trustworthyThreshold: trustworthyThreshold ?? this.trustworthyThreshold,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
    );
  }

  void clear() {
    positions.clear();
    positionGroups.clear();
  }

  void apply(RecognizedReceipt receipt) {
    sumLabel ??= receipt.sumLabel;
    sum ??= receipt.sum;
    company ??= receipt.company;

    receipt.sumLabel = sumLabel;
    receipt.sum = sum;
    receipt.company = company;

    for (final position in receipt.positions) {
      _applyPosition(position);
    }
  }

  void _applyPosition(RecognizedPosition position) {
    final groups = positionGroups;
    final newGroup = PositionGroup.fromPosition(position);

    if (groups.isEmpty) {
      _addToNewGroup(position, newGroup);
      return;
    }

    groups.sort(
      (a, b) => a
          .mostSimilarPosition(position)
          .ratioProduct(position)
          .compareTo(b.mostSimilarPosition(position).ratioProduct(position)),
    );

    final bestGroup = groups.last;
    final bestSim = bestGroup.mostSimilarPosition(position);
    final bestRatio = bestSim.ratioProduct(position);

    if (bestRatio < similarityThreshold) {
      _addToNewGroup(position, newGroup);
    } else {
      _addToExistingGroup(position, bestGroup);
    }
  }

  void _addToExistingGroup(RecognizedPosition position, PositionGroup group) {
    position.group = group;
    position.operation = Operation.updated;

    if (group.positions.length >= maxCacheSize) {
      group.positions.removeAt(0);
    }

    group.positions.add(position);
  }

  void _addToNewGroup(RecognizedPosition position, PositionGroup group) {
    position.group = group;
    position.operation = Operation.added;
    positionGroups.add(group);
  }

  void consolidatePositions() {
    final List<RecognizedPosition> positions = [];

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthyPosition();

      if (group.positions.length >= minScans) {
        positions.add(mostTrustworthy);
      }

      if (isValid) break;
    }

    positions.removeWhere((p) => p.trustworthiness < trustworthyThreshold);

    this.positions.clear();
    this.positions.addAll(positions);
  }
}
