import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedProduct extends RecognizedEntity<String> {
  RecognizedProduct({required super.line, required super.value})
    : formattedValue = value;

  RecognizedProduct copyWith({String? value, TextLine? line}) {
    return RecognizedProduct(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => value;

  @override
  String formattedValue;
}

final class RecognizedPrice extends RecognizedEntity<num> {
  RecognizedPrice({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
