import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a product name recognized from a receipt.
///
/// Contains the product description and methods to normalize and format it.
final class RecognizedProduct extends RecognizedEntity<String> {
  /// Confidence score for this recognition (0-100).
  int confidence;

  /// The position this product belongs to, if any.
  RecognizedPosition? position;

  /// Parsing options (user config or defaults).
  final ReceiptOptions options;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.confidence = 0,
    this.position,
    ReceiptOptions? options,
  }) : options = options ?? ReceiptOptions.empty();

  /// Creates a [RecognizedProduct] from a JSON map.
  factory RecognizedProduct.fromJson(Map<String, dynamic> json) {
    return RecognizedProduct(
      value: json['value'],
      confidence: json['confidence'] ?? 0,
      line: DummyTextLine(),
      options: ReceiptOptions.empty(), // fallback when deserialized
    );
  }

  /// Creates a copy of this product with optionally updated properties.
  RecognizedProduct copyWith({
    String? value,
    TextLine? line,
    int? confidence,
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

  /// Returns the formatted product text.
  String get text => formattedValue;

  /// Returns the normalized product text using alternatives.
  String get normalizedText =>
      ReceiptNormalizer.normalizeByAlternativeTexts(alternativeTexts) ?? text;

  /// Returns the postfix text after the price, if any.
  String get postfixText =>
      position?.group?.convertToPostfixText(position?.price.line.text ?? '') ??
      '';

  /// Returns the normalized postfix text using keyword matching.
  String get normalizedPostfixText => alternativePostfixTexts.firstWhere(
    (postfixText) =>
        options.foodKeywords.hasMatch(postfixText) ||
        options.nonFoodKeywords.hasMatch(postfixText) ||
        ReceiptPatterns.foodKeywords.hasMatch(postfixText) ||
        ReceiptPatterns.nonFoodKeywords.hasMatch(postfixText),
    orElse: () => '',
  );

  /// Returns alternative product texts from the group.
  List<String> get alternativeTexts => position?.group?.alternativeTexts ?? [];

  /// Returns alternative postfix texts from the group.
  List<String> get alternativePostfixTexts =>
      position?.group?.alternativePostfixTexts ?? [];

  /// True if this product is a cashback (negative price).
  bool get isCashback => (position?.price.value ?? 0.0) < 0;

  /// True if this product is classified as food.
  bool get isFood =>
      options.foodKeywords.hasMatch(normalizedPostfixText) ||
      ReceiptPatterns.foodKeywords.hasMatch(normalizedPostfixText);

  /// True if this product is classified as non-food.
  bool get isNonFood =>
      options.nonFoodKeywords.hasMatch(normalizedPostfixText) ||
      ReceiptPatterns.nonFoodKeywords.hasMatch(normalizedPostfixText);

  /// True if this product represents a discount.
  bool get isDiscount =>
      isCashback &&
      (options.discountKeywords.hasMatch(text) ||
          ReceiptPatterns.discountKeywords.hasMatch(text));

  /// True if this product represents a deposit return.
  bool get isDeposit =>
      isCashback &&
      (options.depositKeywords.hasMatch(text) ||
          ReceiptPatterns.depositKeywords.hasMatch(text));
}
