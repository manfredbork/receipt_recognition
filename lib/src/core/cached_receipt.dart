import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'position_group.dart';
import 'receipt_models.dart';
import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class CachedReceipt extends RecognizedReceipt {
  final int minScans;
  final Duration minDurationBeforeInvalidate;

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
    this.trustworthyThreshold = 20,
    this.maxCacheSize = 20,
    this.minLongReceiptSize = 20,
    super.sumLabel,
    super.sum,
    super.company,
    super.isValid,
  })  : minScans = videoFeed ? 3 : 1,
        minDurationBeforeInvalidate = const Duration(seconds: 3);

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
    bool? isValid,
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
      isValid: isValid ?? this.isValid,
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
    final groups = positionGroups
        .where((g) => g.positions.every((p) => p.timestamp != position.timestamp))
        .toList();

    final newGroup = PositionGroup(position: position);

    if (groups.isEmpty) {
      _addToNewGroup(position, newGroup);
      return;
    }

    groups.sort((a, b) {
      final simA = a.mostSimilar(position).similarity(position);
      final simB = b.mostSimilar(position).similarity(position);
      return simA.compareTo(simB);
    });

    final bestGroup = groups.last;
    final bestSim = bestGroup.mostSimilar(position).similarity(position);

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

  void consolidatePositions() {
    positions.clear();
    final groupsToRemove = <PositionGroup>[];

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthy();

      if (mostTrustworthy?.trustworthiness == null) continue;

      if (mostTrustworthy!.trustworthiness! >= trustworthyThreshold &&
          group.positions.length >= minScans) {
        positions.add(mostTrustworthy);
      }

      if (group.positions.length < minScans &&
          DateTime.now().difference(group.oldestTimestamp()) >= minDurationBeforeInvalidate) {
        groupsToRemove.add(group);
      }

      if (isCorrectSum) return;
    }

    final calcSum = calculatedSum.value;
    if (sum != null && calcSum > sum!.value * sqrt2) {
      final badPositions = List<RecognizedPosition>.from(positions)
        ..sort((a, b) => (a.trustworthiness ?? 0).compareTo(b.trustworthiness ?? 0));

      while (calculatedSum.value > sum!.value && badPositions.isNotEmpty) {
        positions.remove(badPositions.removeLast());
      }
    }
  }

  RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final normalized = receipt.positions.map((position) {
      final mostTrustworthy = position.group?.mostTrustworthy(
        defaultPosition: position,
        priceRequired: true,
      ) ??
          position;

      final similarPositions = position.group?.positions.where(
            (p) =>
        partialRatio(p.product.value, mostTrustworthy.product.value) == 100 &&
            p.price.formattedValue == position.price.formattedValue,
      ) ??
          [];

      final words = mostTrustworthy.product.value.split(' ');
      int len = words.length;

      for (final sim in similarPositions) {
        final simWords = sim.product.value.split(' ');
        if (len > 2 && simWords.length < len) len = simWords.length;
        if (len > 2 && simWords[len - 1] != words[len - 1]) len--;
      }

      while (len > 2 && words[len - 1].replaceAll(RegExp(r'[^A-Z%]'), '').isEmpty) {
        len--;
      }

      final normalizedValue = words.take(len).join(' ');
      final newProduct = mostTrustworthy.product.copyWith(value: normalizedValue);

      return mostTrustworthy.copyWith(product: newProduct);
    }).toList();

    return receipt.copyWith(positions: normalized);
  }

  void validate(RecognizedReceipt receipt) {
    receipt.isValid = receipt.isCorrectSum && (areEnoughScans || isLongReceipt);
  }

  bool get isLongReceipt => positions.length >= minLongReceiptSize;

  bool get areEnoughScans {
    final groups = positionGroups.where(
          (g) => g.positions.any((p) => positions.contains(p)),
    );
    return groups.isNotEmpty && groups.every((g) => g.positions.length >= minScans);
  }

  RecognizedReceipt get receipt => copyWith();
}
