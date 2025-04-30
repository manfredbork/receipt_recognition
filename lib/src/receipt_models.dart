import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

abstract class Valuable<T> {
  final T value;

  Valuable({required this.value});

  String get formattedValue;
}

abstract class RecognizedEntity<T> extends Valuable<T> {
  final TextLine line;

  RecognizedEntity({required this.line, required super.value});
}

class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  String get formattedValue => value;
}

class RecognizedCompany extends RecognizedUnknown {
  RecognizedCompany({required super.line, required super.value});
}

class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

class RecognizedSumLabel extends RecognizedUnknown {
  RecognizedSumLabel({required super.line, required super.value});
}

class RecognizedSum extends RecognizedAmount {
  RecognizedSum({required super.line, required super.value});
}

class CalculatedSum extends Valuable<double> {
  CalculatedSum({required super.value});

  @override
  String get formattedValue => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(value);
}

class RecognizedPosition {
  final RecognizedEntity product;
  final RecognizedEntity price;
  final String? key;

  RecognizedPosition({required this.product, required this.price, this.key});

  @override
  bool operator ==(Object other) =>
      other is RecognizedPosition && price == other.price && key == other.key;

  @override
  int get hashCode => Object.hash(price, key);
}

class RecognizedReceipt {
  final List<RecognizedPosition> positions;
  final RecognizedSum? sum;
  final RecognizedCompany? company;

  RecognizedReceipt({required this.positions, this.sum, this.company});

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));
}
