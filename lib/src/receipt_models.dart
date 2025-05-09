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

  init();

  optimize(RecognizedReceipt receipt);

  close();
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

  RecognizedPosition? previous;

  int trustworthiness;

  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    this.previous,
    trustworthiness,
  }) : trustworthiness = trustworthiness ?? 0;

  int similarity(RecognizedPosition other) {
    if (timestamp == other.timestamp) {
      return 0;
    }

    return ratio(product.value, other.product.value);
  }
}

final class RecognizedReceipt {
  List<RecognizedPosition> positions;

  RecognizedSumLabel? sumLabel;

  RecognizedSum? sum;

  RecognizedCompany? company;

  DateTime timestamp;

  RecognizedReceipt({
    required this.positions,
    this.sumLabel,
    this.sum,
    this.company,
    timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory RecognizedReceipt.empty() {
    return RecognizedReceipt(positions: []);
  }

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}

final class CachedReceipt extends RecognizedReceipt {
  List<PositionGroup> positionGroups;

  int minScans;

  int similarityThreshold;

  int maxCacheSize;

  CachedReceipt({
    required super.positions,
    required this.positionGroups,
    required this.minScans,
    this.similarityThreshold = 50,
    this.maxCacheSize = 100,
  });

  CachedReceipt.clone(CachedReceipt cachedReceipt)
    : this(
        positions: cachedReceipt.positions,
        positionGroups: cachedReceipt.positionGroups,
        minScans: cachedReceipt.minScans,
        similarityThreshold: cachedReceipt.similarityThreshold,
        maxCacheSize: cachedReceipt.maxCacheSize,
      );

  factory CachedReceipt.fromVideoFeed() {
    return CachedReceipt(positions: [], positionGroups: [], minScans: 3);
  }

  factory CachedReceipt.fromImages() {
    return CachedReceipt(positions: [], positionGroups: [], minScans: 1);
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
      final groups = positionGroups.where(
        (g) => g.positions.every((p) => p.timestamp != position.timestamp),
      );

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
          group.positions.add(position);
        } else {
          positionGroups.add(PositionGroup(position: position));
        }

        if (group.positions.length > maxCacheSize) {
          group.positions.remove(group.positions.first);
        }
      } else {
        positionGroups.add(PositionGroup(position: position));
      }
    }
  }

  void merge({videoFeed}) {
    positions.clear();

    for (final group in positionGroups) {
      final mostTrustworthy = group.mostTrustworthy();

      positions.add(mostTrustworthy);
    }
  }

  RecognizedReceipt get receipt {
    positions.sort(
      (a, b) => a.timestamp.millisecondsSinceEpoch.compareTo(
        b.timestamp.millisecondsSinceEpoch,
      ),
    );

    return CachedReceipt.clone(this);
  }
}

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required position}) : positions = [position];

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
