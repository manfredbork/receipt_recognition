import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';

abstract class RecognizedEntity<T> {
  final TextLine line;
  final T value;

  RecognizedEntity({required this.line, required this.value});

  get formattedValue;
}

class RecognizedUnknown extends RecognizedEntity<String> {
  RecognizedUnknown({required super.line, required super.value});

  @override
  get formattedValue => value;
}

class RecognizedCompany extends RecognizedEntity<String> {
  RecognizedCompany({required super.line, required super.value});

  @override
  get formattedValue => value;
}

class RecognizedAmount extends RecognizedEntity<num> {
  RecognizedAmount({required super.line, required super.value});

  @override
  get formattedValue => NumberFormat.decimalPatternDigits(
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

class RecognizedPosition {
  final RecognizedEntity product;
  final RecognizedEntity price;

  RecognizedPosition({required this.product, required this.price});
}

class RecognizedReceipt {
  final List<RecognizedPosition> positions;
  final RecognizedSum? sum;
  final RecognizedCompany? company;

  RecognizedReceipt({required this.positions, this.sum, this.company});

  get isValid => calculatedSum == sum?.formattedValue;

  get calculatedSum => NumberFormat.decimalPatternDigits(
    locale: Intl.defaultLocale,
    decimalDigits: 2,
  ).format(positions.fold(0.0, (a, b) => a + b.price.value));
}
