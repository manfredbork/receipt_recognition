import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

/// A formatter class with static methods to format and parse numbers properly.
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
  String get formattedValue => format(value);
}

/// A recognized value of type [T] extracted from a [TextLine].
abstract class RecognizedEntity<T> extends Valuable<T> {
  /// The [TextLine] from which the value was recognized.
  final TextLine line;

  /// Creates a [RecognizedEntity] from the given [line] and [value].
  RecognizedEntity({required this.line, required super.value});
}

/// Represents a recognized company name on a receipt.
final class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.line, required super.value});

  @override
  String format(String value) => value;
}

/// A recognized entity with an untyped or string value.
final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String format(String value) => value;
}

/// Represents a label indicating a sum on the receipt (e.g., "Total", "Summe").
final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.line, required super.value});

  @override
  String format(String value) => value;
}

/// Represents a recognized numeric amount (e.g., price).
final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

/// Represents the final total sum amount recognized from the receipt.
final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

/// Represents a computed sum calculated from individual line item prices.
final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

/// Represents a product name recognized from a receipt with alias tracking and similarity logic.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Minimum similarity threshold used for comparison.
  final int similarity;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.similarity = 75,
  });

  @override
  String format(String value) => value;
}

/// Represents the price of a product recognized from a receipt.
final class RecognizedPrice extends RecognizedEntity<num> {
  RecognizedPrice({required super.line, required super.value});

  @override
  String format(num value) => Formatter.format(value);
}

/// Represents a line item on a receipt, consisting of a product and its price.
final class RecognizedPosition {
  /// The recognized product name.
  final RecognizedProduct product;

  /// The recognized product price.
  final RecognizedPrice price;

  /// The similarity threshold.
  final int _similarityThreshold;

  RecognizedPosition({
    required this.product,
    required this.price,
    similarityThreshold = 50,
  }) : _similarityThreshold = similarityThreshold;

  /// Checks whether this position is similar to [other].
  bool isSimilar(RecognizedPosition other) {
    return ratio(product.value, other.product.value) > _similarityThreshold &&
        price.formattedValue == other.price.formattedValue;
  }
}

/// Represents a fully recognized receipt, including products, sum, and store information.
final class RecognizedReceipt {
  /// The list of recognized line items on the receipt.
  final List<RecognizedPosition> positions;

  /// The recognized sum label from the receipt, if available.
  final RecognizedSumLabel? sumLabel;

  /// The recognized total sum from the receipt, if available.
  final RecognizedSum? sum;

  /// The recognized company name, if available.
  final RecognizedCompany? company;

  RecognizedReceipt({
    required this.positions,
    this.sumLabel,
    this.sum,
    this.company,
  });

  /// Whether the receipt is considered valid (e.g., sum matches and all products are trusted).
  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;

  /// Calculates the total sum from all line item prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}
