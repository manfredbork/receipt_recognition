import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedProduct extends RecognizedEntity<String> {
  int confidence;
  RecognizedPosition? position;

  RecognizedProduct({
    required super.line,
    required super.value,
    this.confidence = 0,
    this.position,
  });

  RecognizedProduct copyWith({
    String? value,
    TextLine? line,
    int? confidence,
    RecognizedPosition? position,
  }) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
      confidence: confidence ?? this.confidence,
      position: position ?? this.position,
    );
  }

  @override
  String format(String value) => ReceiptFormatter.trim(value);

  String get text => formattedValue;

  String get normalizedText =>
      ReceiptNormalizer.normalizeByAlternativeTexts(alternativeTexts) ?? text;

  List<String> get alternativeTexts => position?.group?.alternativeTexts ?? [];
}
