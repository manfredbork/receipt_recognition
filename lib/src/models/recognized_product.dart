import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Product name recognized from a receipt.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Confidence for this product recognition.
  Confidence? confidence;

  /// The position this product belongs to, if any.
  RecognizedPosition? position;

  /// Parsing options (user config or defaults).
  final ReceiptOptions options;

  /// Creates a recognized product from [value] and [line].
  RecognizedProduct({
    required super.line,
    required super.value,
    this.confidence,
    this.position,
    ReceiptOptions? options,
  }) : options = options ?? ReceiptOptions.empty();

  /// Creates a recognized product from JSON.
  factory RecognizedProduct.fromJson(Map<String, dynamic> json) {
    final rawValue = json['value'];
    final value = (rawValue is String) ? rawValue : (rawValue ?? '').toString();
    final conf = json['confidence'];
    final confValue =
        conf is int ? conf : int.tryParse(conf?.toString() ?? '0') ?? 0;

    return RecognizedProduct(
      value: value,
      confidence: Confidence(value: confValue),
      line: DummyTextLine(),
      options: ReceiptOptions.empty(),
    );
  }

  /// Returns a copy with updated fields.
  RecognizedProduct copyWith({
    String? value,
    TextLine? line,
    Confidence? confidence,
    RecognizedPosition? position,
    ReceiptOptions? options,
  }) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
      confidence: confidence ?? this.confidence,
      position: position ?? this.position,
      options: options ?? this.options,
    );
  }

  @override
  String format(String value) => ReceiptFormatter.trim(value);

  /// Formatted product text.
  String get text => formattedValue;

  /// Normalized product text using group alternatives.
  String get normalizedText =>
      ReceiptNormalizer.normalizeByAlternativeTexts(alternativeTexts) ?? text;

  /// Postfix text after the price, if any.
  String get postfixText =>
      position?.group?.convertToPostfixText(position?.price.line.text ?? '') ??
      '';

  /// Normalized postfix text using keyword matching.
  String get normalizedPostfixText => alternativePostfixTexts.firstWhere(
    (postfixText) =>
        options.foodKeywords.hasMatch(postfixText) ||
        options.nonFoodKeywords.hasMatch(postfixText) ||
        ReceiptPatterns.foodKeywords.hasMatch(postfixText) ||
        ReceiptPatterns.nonFoodKeywords.hasMatch(postfixText),
    orElse: () => '',
  );

  /// Alternative product texts from the group.
  List<String> get alternativeTexts => position?.group?.alternativeTexts ?? [];

  /// Alternative postfix texts from the group.
  List<String> get alternativePostfixTexts =>
      position?.group?.alternativePostfixTexts ?? [];

  /// Percentage frequency of the most common alternative text.
  int get textConsensusRatio {
    final alts = alternativeTexts;
    if (alts.length <
        ReceiptConstants.optimizerPrecisionHigh *
            ReceiptConstants.heuristicQuarter) {
      return 0;
    }
    final counts = <String, int>{};
    for (final t in alts) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    var maxCount = 0;
    for (final v in counts.values) {
      if (v > maxCount) maxCount = v;
    }
    return ((maxCount / alts.length) * 100).round();
  }

  /// Map of each unique alternative text to its percentage frequency.
  Map<String, int> get alternativeTextPercentages {
    final alts = alternativeTexts;
    if (alts.isEmpty) return const {};
    final total = alts.length;
    final counts = <String, int>{};
    for (final t in alts) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final result = <String, int>{};
    counts.forEach((k, v) => result[k] = ((v / total) * 100).round());
    return result;
  }

  /// Whether this product is a cashback (negative price).
  bool get isCashback => (position?.price.value ?? 0.0) < 0;

  /// Whether this product is classified as food.
  bool get isFood =>
      options.foodKeywords.hasMatch(normalizedPostfixText) ||
      ReceiptPatterns.foodKeywords.hasMatch(normalizedPostfixText);

  /// Whether this product is classified as non-food.
  bool get isNonFood =>
      options.nonFoodKeywords.hasMatch(normalizedPostfixText) ||
      ReceiptPatterns.nonFoodKeywords.hasMatch(normalizedPostfixText);

  /// Whether this product represents a discount.
  bool get isDiscount =>
      isCashback &&
      (options.discountKeywords.hasMatch(text) ||
          ReceiptPatterns.discountKeywords.hasMatch(text));

  /// Whether this product represents a deposit return.
  bool get isDeposit =>
      isCashback &&
      (options.depositKeywords.hasMatch(text) ||
          ReceiptPatterns.depositKeywords.hasMatch(text));
}
