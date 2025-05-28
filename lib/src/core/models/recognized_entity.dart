import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

enum Operation { none, added, updated }

abstract class Valuable<T> {
  final T value;

  Valuable({required this.value});

  String format(T value);

  String get formattedValue => format(value);
}

abstract class RecognizedEntity<T> extends Valuable<T> {
  final TextLine line;

  RecognizedEntity({required super.value, required this.line});
}

final class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.value, required super.line});

  RecognizedCompany copyWith({String? value, TextLine? line}) {
    return RecognizedCompany(
      value: value ?? this.value,
      line: line ?? this.line,
    );
  }

  @override
  String format(String value) => value.toUpperCase();
}

final class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.value, required super.line});

  @override
  String format(String value) => value;
}

final class RecognizedSumLabel extends RecognizedEntity<String> {
  RecognizedSumLabel({required super.value, required super.line});

  @override
  String format(String value) => value;
}

final class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.value, required super.line});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

final class RecognizedSum extends RecognizedEntity<num> {
  RecognizedSum({required super.value, required super.line});

  RecognizedSum copyWith({num? value, TextLine? line}) {
    return RecognizedSum(value: value ?? this.value, line: line ?? this.line);
  }

  @override
  String format(num value) => ReceiptFormatter.format(value);
}

final class CalculatedSum extends Valuable<num> {
  CalculatedSum({required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
