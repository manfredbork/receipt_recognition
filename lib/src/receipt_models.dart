import 'package:diffutil_dart/diffutil.dart';
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

  /// Formats value to a string.
  String format(T value);

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

/// A formatter class with a static method to format number properly.
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

/// A base class to manage alternative values (e.g., product, price).
final class RecognizedAliases<T> extends RecognizedEntity<T> {
  /// A list of alternative values or aliases for the entity.
  final List<T> valueAliases;

  /// Trustworthiness score (0–100) based on frequency of alias matches.
  int trustworthiness;

  RecognizedAliases({required super.line, required super.value})
    : valueAliases = [value],
      formattedValue = value.toString(),
      trustworthiness = 0;

  /// Removes entry if list has more than 100 entries and then adds a new value alias.
  void addValueAlias(T valueAlias) {
    if (valueAliases.length > 100) {
      valueAliases.remove(valueAliases.first);
    }

    valueAliases.add(valueAlias);
  }

  /// Replaces all existing value aliases with [valueAliases].
  void updateValueAliases(List<T> valueAliases) {
    this.valueAliases.clear();
    this.valueAliases.addAll(valueAliases);
  }

  /// Calculates the trustworthiness score and determines the most reliable alias.
  void calculateTrustworthiness() {
    final Map<T, int> rank = {};
    for (final value in valueAliases) {
      rank[value] = (rank[value] ?? 0) + 1;
    }

    final sorted = List.from(rank.entries)
      ..sort((a, b) => a.value.compareTo(b.value));

    if (sorted.isNotEmpty) {
      formattedValue = format(sorted.last.key);
      trustworthiness = (sorted.last.value / valueAliases.length * 100).toInt();
    }
  }

  /// Formats value to a string.
  @override
  String format(T value) {
    return value.toString();
  }

  /// The most trusted value after alias analysis.
  @override
  String formattedValue;
}

/// A recognized entity with an untyped or string value.
final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String format(String value) => value;

  @override
  String get formattedValue => value;
}

/// Represents a recognized company name on a receipt.
final class RecognizedCompany extends RecognizedUnknown {
  RecognizedCompany({required super.line, required super.value});
}

/// Represents a recognized numeric amount (e.g., price).
final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value})
    : formattedValue = Formatter.format(value);

  @override
  String format(num value) => Formatter.format(value);

  @override
  String formattedValue;
}

/// Represents a label indicating a sum on the receipt (e.g., "Total", "Summe").
final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.line, required super.value});

  @override
  String format(String value) => value;

  @override
  String get formattedValue => value;
}

/// Represents the final total sum amount recognized from the receipt.
final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);

  @override
  String get formattedValue => format(value);
}

/// Represents a computed sum calculated from individual line item prices.
final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => Formatter.format(value);

  @override
  String get formattedValue => format(value);
}

/// Represents a product name recognized from a receipt with alias tracking and similarity logic.
final class RecognizedProduct extends RecognizedAliases<String> {
  /// Minimum similarity threshold used for comparison.
  final int similarity;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.similarity = 75,
  });

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
final class RecognizedPrice extends RecognizedAliases<num> {
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
    return product.isSimilar(other.product) || other.product.isSimilar(product);
  }

  /// Checks whether this position is equal to [other].
  @override
  bool operator ==(Object other) =>
      other is RecognizedPosition &&
      product.value == other.product.value &&
      price.formattedValue == other.price.formattedValue;

  /// Generates hash from product and price.
  @override
  int get hashCode => Object.hash(product.value, price.value);
}

/// A [ListDiffDelegate] for comparing lists of [RecognizedPosition] items.
class PositionListDiff extends ListDiffDelegate<RecognizedPosition> {
  /// Creates a diff delegate for [oldList] and [newList].
  PositionListDiff(super.oldList, super.newList);

  /// Always returns `false`, treating item contents as changed.
  @override
  bool areContentsTheSame(int oldItemPosition, int newItemPosition) {
    return false;
  }

  /// Returns whether items are the same using [isSimilar].
  @override
  bool areItemsTheSame(int oldItemPosition, int newItemPosition) {
    return oldList[oldItemPosition].isSimilar(newList[newItemPosition]);
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
  CalculatedSum get calculatedSum => CalculatedSum(
    value: positions.fold(0.0, (a, b) => a + num.parse(b.price.formattedValue)),
  );
}
