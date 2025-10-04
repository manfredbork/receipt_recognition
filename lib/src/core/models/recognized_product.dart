import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a product name recognized from a receipt.
///
/// Contains the product description and methods to normalize and format it.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Confidence assessment for this product recognition, including value and weight.
  Confidence? confidence;

  /// The position this product belongs to, if any.
  RecognizedPosition? position;

  /// Parsing options (user config or defaults).
  final ReceiptOptions options;

  /// Creates a recognized product from [value] and source [line].
  RecognizedProduct({
    required super.line,
    required super.value,
    this.confidence,
    this.position,
    ReceiptOptions? options,
  }) : options = options ?? ReceiptOptions.empty();

  /// Creates a product entity from a JSON map.
  factory RecognizedProduct.fromJson(Map<String, dynamic> json) {
    return RecognizedProduct(
      value: json['value'],
      confidence: Confidence(value: json['confidence'] ?? 0),
      line: DummyTextLine(),
      options: ReceiptOptions.empty(),
    );
  }

  /// Creates a copy with optionally updated properties.
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

  /// Formats the product text by trimming it.
  @override
  String format(String value) => ReceiptFormatter.trim(value);

  /// The formatted product text.
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
