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

  int trustworthiness;

  int scans;

  RecognizedPosition({
    required this.product,
    required this.price,
    trustworthiness,
    scans,
  }) : trustworthiness = trustworthiness ?? 0,
       scans = scans ?? 1;

  int similarity(RecognizedPosition other) {
    if (price.formattedValue == other.price.formattedValue) {
      return ratio(product.value, other.product.value);
    }

    return 0;
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

  bool isValid([videoFeed = false]) {
    if (videoFeed && positions.any((p) => p.scans < 1)) {
      return false;
    }

    return calculatedSum.formattedValue == sum?.formattedValue;
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}

final class CachedReceipt extends RecognizedReceipt {
  List<PositionGroup> positionGroups;

  CachedReceipt({required super.positions, required this.positionGroups});

  factory CachedReceipt.empty() {
    return CachedReceipt(positions: [], positionGroups: []);
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
      position.scans++;

      final groups = positionGroups.where(
        (g) =>
            g.mostSimilar(position).price.formattedValue ==
            position.price.formattedValue,
      );

      if (groups.isNotEmpty) {
        try {
          final group = groups.reduce(
            (a, b) =>
                a.mostSimilar(position).similarity(position) >
                        b.mostSimilar(position).similarity(position)
                    ? a
                    : b,
          );

          if (group.mostSimilar(position).similarity(position) > 75) {
            group.positions.add(position);
          } else {
            positionGroups.add(PositionGroup(position: position));
          }

          if (group.positions.length > 100) {
            group.positions.remove(group.positions.first);
          }
        } catch (_) {}
      } else {
        positionGroups.add(PositionGroup(position: position));
      }
    }
  }

  void merge() {
    positions.clear();

    for (final group in positionGroups) {
      positions.add(group.mostTrustworthy());
    }
  }
}

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required position}) : positions = [position];

  RecognizedPosition mostTrustworthy() {
    final Map<String, int> rank = {};

    for (final position in positions) {
      final value = position.product.value;

      if (rank.containsKey(value)) {
        rank[value] = rank[value]! + 1;
      } else {
        rank[value] = 1;
      }
    }

    final ranked = List.from(rank.entries)
      ..sort((a, b) => a.value.compareTo(b.value));

    if (ranked.isNotEmpty) {
      final position = positions.firstWhere(
        (p) => p.product.value == ranked.last.key,
      );

      position.trustworthiness =
          (ranked.last.value / positions.length * 100).toInt();

      return position;
    }

    return positions.first;
  }

  RecognizedPosition mostSimilar(RecognizedPosition position) {
    return positions.reduce(
      (a, b) => a.similarity(position) > b.similarity(position) ? a : b,
    );
  }
}
