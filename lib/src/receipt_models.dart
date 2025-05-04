import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/ratios/simple_ratio.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

abstract class Optimizer {
  init();

  optimize(RecognizedReceipt receipt);

  close();
}

abstract class Valuable<T> {
  final T value;

  Valuable({required this.value});

  String get formattedValue;
}

abstract class RecognizedEntity<T> extends Valuable<T> {
  final TextLine line;

  RecognizedEntity({required this.line, required super.value});
}

class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String get formattedValue => value;
}

class RecognizedCompany extends RecognizedUnknown {
  RecognizedCompany({required super.line, required super.value});
}

class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

class RecognizedSumLabel extends RecognizedUnknown {
  RecognizedSumLabel({required super.line, required super.value});
}

class RecognizedSum extends RecognizedAmount {
  RecognizedSum({required super.line, required super.value});
}

class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

class RecognizedProduct extends RecognizedUnknown {
  final List<String> valueAliases;
  final int similarity;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.similarity = 75,
  }) : valueAliases = [value],
       formattedValue = value,
       trustworthiness = 0;

  void addValueAlias(String valueAlias) {
    if (valueAliases.length < 10) {
      valueAliases.add(valueAlias);
    }

    calculateTrustworthiness();
  }

  void updateValueAliases(List<String> valueAliases) {
    this.valueAliases.clear();
    this.valueAliases.addAll(valueAliases);

    calculateTrustworthiness();
  }

  void calculateTrustworthiness() {
    if (valueAliases.length > 3) {
      final Map<String, int> rank = {};

      for (final value in valueAliases) {
        if (rank.containsKey(value)) {
          rank[value] = rank[value]! + 1;
        } else {
          rank[value] = 1;
        }
      }

      final sorted = List.from(rank.entries)
        ..sort((a, b) => a.value.compareTo(b.value));

      if (sorted.isNotEmpty) {
        formattedValue = sorted.last.key;
        trustworthiness =
            (sorted.last.value / valueAliases.length * 100).toInt();
      }
    }
  }

  bool isSimilar(RecognizedProduct other) {
    try {
      extractOne(
        query: other.value,
        choices: valueAliases,
        cutoff: similarity,
        ratio: SimpleRatio(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  String formattedValue;

  int trustworthiness;
}

class RecognizedPrice extends RecognizedAmount {
  RecognizedPrice({required super.line, required super.value});
}

class RecognizedPosition {
  final RecognizedProduct product;
  final RecognizedPrice price;

  RecognizedPosition({required this.product, required this.price});
}

class RecognizedReceipt {
  final List<RecognizedPosition> positions;
  final RecognizedSum? sum;
  final RecognizedCompany? company;

  RecognizedReceipt({required this.positions, this.sum, this.company});

  bool get isValid =>
      calculatedSum.formattedValue == sum?.formattedValue &&
      positions.every((p) => p.product.trustworthiness > 0);

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}
