import 'position_group.dart';
import 'position_normalizer.dart';
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
    this.maxCacheSize = 10,
    this.minLongReceiptSize = 20,
    super.sumLabel,
    super.sum,
    super.company,
    super.scanComplete = false,
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
    bool? scanComplete,
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
      scanComplete: scanComplete ?? this.scanComplete,
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
      final simA = a.mostSimilarPosition(position).similarity(position);
      final simB = b.mostSimilarPosition(position).similarity(position);
      return simA.compareTo(simB);
    });

    final bestGroup = groups.last;
    final bestSim = bestGroup
        .mostSimilarPosition(position)
        .similarity(position);

    if (bestSim >= similarityThreshold) {
      _addToExistingGroup(position, bestGroup);
    } else {
      _addToNewGroup(position, newGroup);
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

  RecognizedReceipt normalizeFromCache(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      final mostTrustworthy = position.group.mostTrustworthyPosition(
        trustworthyThreshold: trustworthyThreshold,
        orElse: () => position,
      );
      positions.add(mostTrustworthy);
    }

    return receipt.copyWith(
      positions: PositionNormalizer.normalize(positions),
    );
  }

  void consolidatePositions() {
    positions.clear();

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthyPosition(
        trustworthyThreshold: trustworthyThreshold,
        orElse: () => group.positions.first,
      );

      positions.add(mostTrustworthy);

      if (isCorrectSum) return;
    }

    final groups = positionGroups.where(
      (g) => g.positions.any((p) => positions.contains(p)),
    );
    scanComplete =
        groups.isNotEmpty &&
        groups.every((g) => g.positions.length >= minScans);
  }

  bool get isLongReceipt => positions.length >= minLongReceiptSize;

  RecognizedReceipt get normalizedReceipt => normalizeFromCache(copyWith());
}
