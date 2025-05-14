import 'position_group.dart';
import 'receipt_models.dart';
import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class CachedReceipt extends RecognizedReceipt {
  final int minScans;

  List<PositionGroup> positionGroups;
  bool videoFeed;
  int similarityThreshold;
  int trustworthyThreshold;
  int maxCacheSize;
  int minLongReceiptSize;

  CachedReceipt({
    required super.positions,
    required super.timestamp,
    required this.positionGroups,
    required this.videoFeed,
    this.similarityThreshold = 50,
    this.trustworthyThreshold = 25,
    this.maxCacheSize = 20,
    this.minLongReceiptSize = 20,
    super.sumLabel,
    super.sum,
    super.company,
  }) : minScans = videoFeed ? 3 : 1;

  @override
  CachedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    List<PositionGroup>? positionGroups,
    bool? videoFeed,
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
      positionGroups: positionGroups ?? this.positionGroups,
      videoFeed: videoFeed ?? this.videoFeed,
      similarityThreshold: similarityThreshold ?? this.similarityThreshold,
      trustworthyThreshold: trustworthyThreshold ?? this.trustworthyThreshold,
      maxCacheSize: maxCacheSize ?? this.maxCacheSize,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
    );
  }

  factory CachedReceipt.fromVideoFeed() => CachedReceipt(
    positions: [],
    timestamp: DateTime.now(),
    positionGroups: [],
    videoFeed: true,
  );

  factory CachedReceipt.fromImages() => CachedReceipt(
    positions: [],
    timestamp: DateTime.now(),
    positionGroups: [],
    videoFeed: false,
  );

  void clear() {
    positions.clear();
    positionGroups.clear();
  }

  void apply(RecognizedReceipt receipt) {
    sumLabel ??= receipt.sumLabel;
    sum ??= receipt.sum;
    company ??= receipt.company;

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

    groups.sort((a, b) {
      final simA = a.mostSimilarPosition(
        compare: position,
        similarityThreshold: similarityThreshold,
        orElse: () => position,
      );
      final ratioA = simA.ratioProduct(position);
      final simB = b.mostSimilarPosition(
        compare: position,
        similarityThreshold: similarityThreshold,
        orElse: () => position,
      );
      final ratioB = simB.ratioProduct(position);
      if (simA == position && simB == position) return 0;
      if (simA == position) return 1;
      if (simB == position) return -1;
      return ratioA.compareTo(ratioB);
    });

    final bestGroup = groups.last;
    final bestSim = bestGroup.mostSimilarPosition(
      compare: position,
      similarityThreshold: similarityThreshold,
      orElse: () => position,
    );

    if (bestSim.group.positions.isEmpty) {
      _addToNewGroup(position, newGroup);
    } else {
      _addToExistingGroup(position, bestGroup);
    }
  }

  void _addToExistingGroup(RecognizedPosition position, PositionGroup group) {
    position.group = group;
    position.operation = Operation.updated;
    group.positions.add(position);
    if (group.positions.length > maxCacheSize) {
      group.positions.removeAt(0);
    }
  }

  void _addToNewGroup(RecognizedPosition position, PositionGroup group) {
    position.group = group;
    position.operation = Operation.added;
    positionGroups.add(group);
  }

  void consolidatePositions() {
    final isLongReceipt = positions.length >= minLongReceiptSize;

    positions.clear();

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthyPosition(
        compare: group.positions.first,
        trustworthyThreshold: trustworthyThreshold,
        orElse: () => group.positions.first,
      );

      if (group.positions.length >= minScans || isLongReceipt) {
        positions.add(mostTrustworthy);
      }

      if (isValid) return;
    }
  }
}
