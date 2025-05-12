import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';

import 'receipt_models.dart';

final class RecognizedPosition {
  final RecognizedProduct product;

  final RecognizedPrice price;

  DateTime timestamp;

  int? trustworthiness;

  PositionGroup? group;

  Operation? operation;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    this.trustworthiness,
    this.group,
    this.operation,
  });

  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    int? trustworthiness,
    PositionGroup? group,
    Operation? operation,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      trustworthiness: trustworthiness ?? this.trustworthiness,
      group: group ?? this.group,
      operation: operation ?? this.operation,
    );
  }

  int similarity(RecognizedPosition other) {
    if (timestamp == other.timestamp) {
      return 0;
    }

    return ratio(product.value, other.product.value);
  }
}

final class RecognizedReceipt {
  List<RecognizedPosition> positions;

  DateTime timestamp;

  RecognizedSumLabel? sumLabel;

  RecognizedSum? sum;

  RecognizedCompany? company;

  bool isValid;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sumLabel,
    this.sum,
    this.company,
    this.isValid = false,
  });

  factory RecognizedReceipt.empty() {
    return RecognizedReceipt(positions: [], timestamp: DateTime.now());
  }

  RecognizedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    int? similarityThreshold,
    int? trustworthyThreshold,
    RecognizedSumLabel? sumLabel,
    RecognizedSum? sum,
    RecognizedCompany? company,
    bool? isValid,
  }) {
    return RecognizedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
      isValid: isValid ?? this.isValid,
    );
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  bool get isCorrectSum => calculatedSum.formattedValue == sum?.formattedValue;
}

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
