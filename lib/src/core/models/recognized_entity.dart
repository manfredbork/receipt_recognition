import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

enum Operation { added, updated }

abstract class Valuable<T> {
  final T value;

  Valuable({required this.value});

  String format(T value);

  String get formattedValue => format(value);
}

abstract class RecognizedEntity<T> extends Valuable<T> {
  final TextLine line;

  RecognizedEntity({required this.line, required super.value});
}

final class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.line, required super.value});

  @override
  String format(String value) => value.toUpperCase();
}

final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String format(String value) => value;
}

final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.line, required super.value});

  @override
  String format(String value) => value;
}

final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
