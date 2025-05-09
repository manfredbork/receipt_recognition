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

  RecognizedPosition? previous;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    this.trustworthiness,
    this.group,
    this.previous,
  });

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

  RecognizedReceipt.clone(CachedReceipt cachedReceipt)
    : this(
        positions: cachedReceipt.positions,
        timestamp: cachedReceipt.timestamp,
      );

  factory RecognizedReceipt.empty() {
    return RecognizedReceipt(positions: [], timestamp: DateTime.now());
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
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
    this.trustworthyThreshold = 20,
    this.maxCacheSize = 20,
    super.isValid = false,
    super.sumLabel,
    super.sum,
    super.company,
  }) : minScans = videoFeed ? 5 : 1;

  CachedReceipt.clone(CachedReceipt cachedReceipt)
    : this(
        positions: cachedReceipt.positions,
        timestamp: cachedReceipt.timestamp,
        positionGroups: cachedReceipt.positionGroups,
        videoFeed: cachedReceipt.videoFeed,
        similarityThreshold: cachedReceipt.similarityThreshold,
        trustworthyThreshold: cachedReceipt.trustworthyThreshold,
        maxCacheSize: cachedReceipt.maxCacheSize,
        isValid: cachedReceipt.isValid,
        sumLabel: cachedReceipt.sumLabel,
        sum: cachedReceipt.sum,
        company: cachedReceipt.company,
      );

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

    RecognizedPosition? previous;

    for (final position in receipt.positions) {
      final groups = positionGroups.where(
        (g) => g.positions.every((p) => p.timestamp != position.timestamp),
      );

      final newGroup = PositionGroup(position: position);

      if (groups.isNotEmpty) {
        final group = groups.reduce(
          (a, b) =>
              a.mostSimilar(position).similarity(position) >
                      b.mostSimilar(position).similarity(position)
                  ? a
                  : b,
        );

        if (group.mostSimilar(position).similarity(position) >
            similarityThreshold) {
          position.group = group;
          position.previous = previous;
          group.positions.add(position);

          if (group.positions.length > maxCacheSize) {
            group.positions.remove(group.positions.first);
          }
        } else {
          position.group = newGroup;
          position.previous = previous;
          positionGroups.add(newGroup);
        }
      } else {
        position.group = newGroup;
        position.previous = previous;
        positionGroups.add(newGroup);
      }

      previous = position;
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
    }
  }

  bool get areMinScansReached {
    final groups = positionGroups.where(
      (g) => g.positions.any((p) => positions.contains(p)),
    );

    if (groups.isNotEmpty) {
      return groups.every((g) => g.positions.length >= minScans);
    }

    return false;
  }

  bool get isCorrectSum => calculatedSum.formattedValue == sum?.formattedValue;

  RecognizedReceipt get receipt {
    return CachedReceipt.clone(this);
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

  RecognizedPosition mostTrustworthy() {
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
            p.product.value == ranked.last.key.$1 &&
            p.price.formattedValue == ranked.last.key.$2,
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
