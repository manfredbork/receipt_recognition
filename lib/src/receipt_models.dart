import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

final class Formatter {
  static String format(num value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);

  static num parse(String value) => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).parse(value);
}

abstract class Optimizer {
  Optimizer({required videoFeed});

  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void close();
}

abstract class Valuable<T> {
  final T value;

  Valuable({required this.value});

  String format(T value);

  String get formattedValue => format(value);
}

abstract class RecognizedEntity<T> extends Valuable<T> {
  final TextLine line;

  RecognizedEntity({required this.line, required super.value});
}

final class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.line, required super.value});

  @override
  String format(String value) => value;
}

final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String format(String value) => value;
}

final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.line, required super.value});

  @override
  String format(String value) => value;
}

final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

final class RecognizedProduct extends RecognizedEntity<String> {
  RecognizedProduct({required super.line, required super.value});

  RecognizedProduct copyWith({String? value, TextLine? line}) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => value;
}

final class RecognizedPrice extends RecognizedEntity<num> {
  RecognizedPrice({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

final class RecognizedPosition {
  final RecognizedProduct product;

  final RecognizedPrice price;

  DateTime timestamp;

  int? trustworthiness;

  PositionGroup? group;

  RecognizedPosition? next;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    this.trustworthiness,
    this.group,
    this.next,
  });

  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    int? trustworthiness,
    PositionGroup? group,
    RecognizedPosition? next,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      trustworthiness: trustworthiness ?? this.trustworthiness,
      group: group ?? this.group,
      next: next ?? this.next,
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

  int minScans;

  CachedReceipt({
    required super.positions,
    required super.timestamp,
    required this.positionGroups,
    required this.videoFeed,
    this.similarityThreshold = 50,
    this.trustworthyThreshold = 25,
    this.maxCacheSize = 10,
    super.sumLabel,
    super.sum,
    super.company,
    super.isValid,
  }) : minScans = videoFeed ? 3 : 1;

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

    for (int i = 0; i < receipt.positions.length; i++) {
      final position = receipt.positions[i];

      RecognizedPosition? next =
          i + 1 < receipt.positions.length ? receipt.positions[i + 1] : null;

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

        final group = groups.last;

        if (group.mostSimilar(position).similarity(position) >=
            similarityThreshold) {
          position.group = group;
          position.next = next;
          group.positions.add(position);

          if (group.positions.length > maxCacheSize) {
            group.positions.remove(group.positions.first);
          }
        } else {
          position.group = newGroup;
          position.next = next;
          positionGroups.add(newGroup);
        }
      } else {
        position.group = newGroup;
        position.next = next;
        positionGroups.add(newGroup);
      }
    }
  }

  void merge() {
    positions.clear();

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthy();

      if (mostTrustworthy.trustworthiness != null) {
        if (mostTrustworthy.trustworthiness! >= trustworthyThreshold &&
            group.positions.length >= minScans) {
          positions.add(mostTrustworthy);
        }
      }

      if (isCorrectSum) {
        break;
      }

      if (sum != null) {
        if (calculatedSum.value > sum!.value * pi) {
          positionGroups.clear();
          break;
        }
      }
    }
  }

  void normalize(RecognizedReceipt receipt, {reorder = false}) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      final mostTrustworthy =
          position.group?.mostTrustworthy(withPrice: false) ?? position;
      final product = position.product.copyWith(
        value: mostTrustworthy.product.value,
      );
      positions.add(
        position.copyWith(
          product: product,
          trustworthiness: mostTrustworthy.trustworthiness,
          group: mostTrustworthy.group,
          next: mostTrustworthy.next,
        ),
      );
    }

    receipt.positions.clear();
    receipt.positions.addAll(positions);
  }

  void validate(RecognizedReceipt receipt) {
    receipt.isValid = receipt.isCorrectSum && areEnoughScans;
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

  RecognizedPosition mostTrustworthy({withPrice = true}) {
    const withoutPrice = '';
    final Map<(String, String), int> rank = {};

    for (final position in positions) {
      final product = position.product.value;
      final price = position.price.formattedValue;
      final key = (product, withPrice ? price : withoutPrice);

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
            (ranked.last.key.$2 == p.price.formattedValue ||
                ranked.last.key.$2 == withoutPrice),
      );

      position.trustworthiness =
          (ranked.last.value / positions.length * 100).toInt();

      return position;
    }

    return positions.last;
  }

  RecognizedPosition mostSimilar(RecognizedPosition position) {
    return positions.reduce(
      (a, b) => a.similarity(position) > b.similarity(position) ? a : b,
    );
  }
}
