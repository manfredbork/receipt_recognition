import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedProduct extends RecognizedEntity<String> {
  final List<String> alternativeTexts = [];

  RecognizedProduct({required super.line, required super.value});

  RecognizedProduct copyWith({String? value, TextLine? line}) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => ReceiptFormatter.trim(value);

  String get text => formattedValue;

  String get normalizedText =>
      ReceiptNormalizer.normalizeByAlternativeTexts(alternativeTexts) ?? text;
}
