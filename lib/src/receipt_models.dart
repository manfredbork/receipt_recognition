import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:fuzzywuzzy/ratios/simple_ratio.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

/// A base class for implementing optimizers that modify or improve a [RecognizedReceipt].
abstract class Optimizer {
  /// Initializes the optimizer. Can be used to prepare resources or state.
  init();

  /// Optimizes the given [RecognizedReceipt].
  optimize(RecognizedReceipt receipt);

  /// Cleans up resources used by the optimizer.
  close();
}

/// Represents a value of type [T] with a formatted string representation.
abstract class Valuable<T> {
  /// The underlying value.
  final T value;

  /// Creates a [Valuable] with the given [value].
  Valuable({required this.value});

  /// Returns the value as a human-readable string.
  String get formattedValue;
}

/// A recognized value of type [T] extracted from a [TextLine].
abstract class RecognizedEntity<T> extends Valuable<T> {
  /// The [TextLine] from which the value was recognized.
  final TextLine line;

  /// Creates a [RecognizedEntity] from the given [line] and [value].
  RecognizedEntity({required this.line, required super.value});
}

/// A recognized entity with an untyped or string value.
final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String get formattedValue => value;
}

/// Represents a recognized company name on a receipt.
final class RecognizedCompany extends RecognizedUnknown {
  RecognizedCompany({required super.line, required super.value});
}

/// Represents a recognized numeric amount (e.g., price, sum).
final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

/// Represents a label indicating a sum on the receipt (e.g., "Total", "Summe").
final class RecognizedSumLabel extends RecognizedUnknown {
  RecognizedSumLabel({required super.line, required super.value});
}

/// Represents the final total sum amount recognized from the receipt.
final class RecognizedSum extends RecognizedAmount {
  RecognizedSum({required super.line, required super.value});
}

/// Represents a computed sum calculated from individual line item prices.
final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

/// Represents a product name recognized from a receipt with alias tracking and similarity logic.
final class RecognizedProduct extends RecognizedUnknown {
  /// A list of alternative names or aliases for the product.
  final List<String> valueAliases;

  /// Minimum similarity threshold used for comparison.
  final int similarity;

  /// Trustworthiness score (0–100) based on frequency of alias matches.
  int trustworthiness;

  /// The most trusted product name after alias analysis.
  @override
  String formattedValue;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.similarity = 75,
  }) : valueAliases = [value],
       formattedValue = value,
       trustworthiness = 0;

  /// Adds a new value alias if the list has fewer than 10 entries.
  void addValueAlias(String valueAlias) {
    if (valueAliases.length < 10) {
      valueAliases.add(valueAlias);
    }
  }

  /// Replaces all existing value aliases with [valueAliases].
  void updateValueAliases(List<String> valueAliases) {
    this.valueAliases.clear();
    this.valueAliases.addAll(valueAliases);
  }

  /// Calculates the trustworthiness score and determines the most reliable alias.
  void calculateTrustworthiness() {
    final Map<String, int> rank = {};
    for (final value in valueAliases) {
      rank[value] = (rank[value] ?? 0) + 1;
    }

    final sorted = List.from(rank.entries)
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sorted.isNotEmpty) {
      formattedValue = sorted.last.key;
      trustworthiness = (sorted.last.value / valueAliases.length * 100).toInt();
    }
  }

  /// Checks whether this product is similar to [other] based on string similarity.
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
}

/// Represents the price of a product recognized from a receipt.
final class RecognizedPrice extends RecognizedAmount {
  RecognizedPrice({required super.line, required super.value});
}

/// Represents a line item on a receipt, consisting of a product and its price.
final class RecognizedPosition {
  /// The recognized product name.
  final RecognizedProduct product;

  /// The recognized product price.
  final RecognizedPrice price;

  RecognizedPosition({required this.product, required this.price});

  /// Checks whether this position is similar to [other].
  bool isSimilar(RecognizedPosition other) {
    return product.isSimilar(other.product) &&
        price.formattedValue == other.price.formattedValue;
  }
}

/// Represents a fully recognized receipt, including products, sum, and store information.
final class RecognizedReceipt {
  /// The list of recognized line items on the receipt.
  final List<RecognizedPosition> positions;

  /// The recognized total sum from the receipt, if available.
  final RecognizedSum? sum;

  /// The recognized company name, if available.
  final RecognizedCompany? company;

  RecognizedReceipt({required this.positions, this.sum, this.company});

  /// Whether the receipt is considered valid (e.g., sum matches and all products are trusted).
  bool get isValid =>
      calculatedSum.formattedValue == sum?.formattedValue &&
      positions.every((p) => p.product.trustworthiness > 0);

  /// Calculates the total sum from all line item prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}
