import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'position_group.dart';
import 'receipt_models.dart';
import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class CachedReceipt extends RecognizedReceipt {
  List<PositionGroup> positionGroups;

  bool videoFeed;

  int similarityThreshold;

  int trustworthyThreshold;

  int maxCacheSize;

  int minLongReceiptSize;

  int minScans;

  Duration minDurationBeforeInvalidate;

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
  }) : minScans = videoFeed ? 3 : 1,
       minDurationBeforeInvalidate = Duration(seconds: 3);

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

  factory CachedReceipt.fromVideoFeed() {
    return CachedReceipt(
      positions: [],
      timestamp: DateTime.now(),
      positionGroups: [],
      videoFeed: true,
    );
  }

  factory CachedReceipt.fromImages() {
    return CachedReceipt(
      positions: [],
      timestamp: DateTime.now(),
      positionGroups: [],
      videoFeed: false,
    );
  }

  void clear() {
    positions.clear();
    positionGroups.clear();
  }

  void apply(RecognizedReceipt receipt) {
    sumLabel = receipt.sumLabel ?? sumLabel;
    sum = receipt.sum ?? sum;
    company = receipt.company ?? company;

    for (final position in receipt.positions) {
      final groups = List<PositionGroup>.from(
        positionGroups.where(
          (g) => g.positions.every((p) => p.timestamp != position.timestamp),
        ),
      );

      final newGroup = PositionGroup(position: position);

      if (groups.isNotEmpty) {
        groups.sort(
          (a, b) => a
              .mostSimilar(position)
              .similarity(position)
              .compareTo(b.mostSimilar(position).similarity(position)),
        );

        PositionGroup group = groups.last;

        if (group.mostSimilar(position).similarity(position) >=
            similarityThreshold) {
          position.group = group;
          position.operation = Operation.updated;
          group.positions.add(position);

          if (group.positions.length > maxCacheSize) {
            group.positions.remove(group.positions.first);
          }
        } else {
          position.group = newGroup;
          position.operation = Operation.added;
          positionGroups.add(newGroup);
        }
      } else {
        position.group = newGroup;
        position.operation = Operation.added;
        positionGroups.add(newGroup);
      }
    }
  }

  void merge() {
    positions.clear();

    final groupsToRemove = [];

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthy();

      if (mostTrustworthy?.trustworthiness != null) {
        if (mostTrustworthy!.trustworthiness! >= trustworthyThreshold &&
            group.positions.length >= minScans) {
          positions.add(mostTrustworthy);
        }

        if (group.positions.length < minScans) {
          final now = DateTime.now();

          if (now.difference(group.oldestTimestamp()) >=
              minDurationBeforeInvalidate) {
            groupsToRemove.add(group);
          }
        }

        if (isCorrectSum) {
          return;
        }
      }
    }

    if (sum != null) {
      if (calculatedSum.value > sum!.value * sqrt2) {
        final badPositions = List<RecognizedPosition>.from(positions)..sort(
          (a, b) => (a.trustworthiness ?? 0).compareTo(b.trustworthiness ?? 0),
        );

        while (calculatedSum.value > sum!.value && badPositions.isNotEmpty) {
          positions.remove(badPositions.last);
          badPositions.removeLast();
        }
      }
    }
  }

  RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      RecognizedPosition mostTrustworthy =
          position.group?.mostTrustworthy(
            defaultPosition: position,
            priceRequired: true,
          ) ??
          position;

      final similarPositions = position.group!.positions.where(
        (p) =>
            partialRatio(p.product.value, mostTrustworthy.product.value) ==
                100 &&
            p.price.formattedValue == position.price.formattedValue,
      );

      final List<String> values = mostTrustworthy.product.value.split(' ');

      int len = values.length;

      String newValue = '';

      if (similarPositions.isNotEmpty) {
        for (final similarPosition in similarPositions) {
          List<String> similarValues = similarPosition.product.value.split(' ');

          if (len > 2 && similarValues.length < len) {
            len = similarValues.length;
          }

          if (len > 2 && similarValues[len - 1] != values[len - 1]) {
            len = len - 1;
          }
        }

        while (len > 2 &&
            values[len - 1].replaceAll(RegExp(r'[^A-Z%]'), '').isEmpty) {
          len = len - 1;
        }

        for (int i = 0; i < len; i++) {
          newValue += values[i] + (i < len - 1 ? ' ' : '');
        }
      }

      final newProduct = mostTrustworthy.product.copyWith(value: newValue);

      positions.add(
        mostTrustworthy.copyWith(
          product: newProduct,
          trustworthiness: mostTrustworthy.trustworthiness,
          timestamp: mostTrustworthy.timestamp,
        ),
      );
    }

    return receipt.copyWith(positions: positions);
  }

  void validate(RecognizedReceipt receipt) {
    receipt.isValid = receipt.isCorrectSum && (areEnoughScans || isLongReceipt);
  }

  bool get isLongReceipt {
    return positions.length >= minLongReceiptSize;
  }

  bool get areEnoughScans {
    final groups = positionGroups.where(
      (g) => g.positions.any((p) => positions.contains(p)),
    );

    if (groups.isNotEmpty) {
      return groups.every((g) => g.positions.length >= minScans);
    }

    return false;
  }

  RecognizedReceipt get receipt {
    return copyWith();
  }
}
