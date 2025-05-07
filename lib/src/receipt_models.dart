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

  final RecognizedReceipt? receipt;

  RecognizedPosition({
    required this.product,
    required this.price,
    this.receipt,
  });

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

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}

final class CachedReceipt extends RecognizedReceipt {
  List<PositionGroup> positionGroups;

  CachedReceipt({
    required this.positionGroups,
    required super.positions,
    super.sumLabel,
    super.sum,
    super.company,
  });

  factory CachedReceipt.fromReceipt(RecognizedReceipt receipt) {
    return CachedReceipt(
      positionGroups: [],
      positions: [],
      sumLabel: receipt.sumLabel,
      sum: receipt.sum,
      company: receipt.company,
    );
  }
}

final class PositionGroup {
  final List<RecognizedPosition> positions;

  PositionGroup({required position}) : positions = [position];

  int similarity(RecognizedPosition position) {
    return positions
        .reduce(
          (a, b) => a.similarity(position) > b.similarity(position) ? a : b,
        )
        .similarity(position);
  }
}
