import 'package:receipt_recognition/receipt_recognition.dart';

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
    this.trustworthyThreshold = 40,
    this.maxCacheSize = 20,
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
    sumLabel = null;
    sum = null;
    company = null;
  }

  void apply(RecognizedReceipt receipt) {
    timestamp = receipt.timestamp;
    sumLabel = receipt.sumLabel ?? sumLabel;
    sum = receipt.sum ?? sum;
    company = receipt.company ?? company;

    for (final position in receipt.positions) {
      _applyPosition(position);
    }
  }

  void _applyPosition(RecognizedPosition position) {
    final newGroup = PositionGroup.fromPosition(position);
    final groups = positionGroups.where((g) {
      return g.positions.every(
            (p) => !p.timestamp.isAtSameMomentAs(position.timestamp),
      );
    }).toList();

    if (groups.isEmpty) {
      _addToNewGroup(position, newGroup);
      return;
    }

    groups.sort((a, b) {
      return a
          .mostSimilarPosition(position)
          .ratioProduct(position)
          .compareTo(b.mostSimilarPosition(position).ratioProduct(position));
    });

    final bestGroup = groups.last;
    final bestSim = bestGroup
        .mostSimilarPosition(position)
        .ratioProduct(position);

    if (bestSim < similarityThreshold) {
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

  Future<void> consolidatePositions() async {
    final List<PositionGroup> groupsToRemove = [];

    positionGroups.sort(
          (b, a) => a.trustworthiness.compareTo(b.trustworthiness),
    );

    for (final group in positionGroups) {
      if (group.positions.length >= minScans) {
        final mostTrustworthy = group.mostTrustworthyPosition();
        if (mostTrustworthy.trustworthiness <= trustworthyThreshold) {
          groupsToRemove.add(mostTrustworthy.group);
        }
      }
      if (isValid) break;
    }

    positionGroups.removeWhere((g) => groupsToRemove.contains(g));

    final sorted = await resolveGraphInIsolate(positionGroups);

    positions
      ..clear()
      ..addAll(sorted);
  }
}
