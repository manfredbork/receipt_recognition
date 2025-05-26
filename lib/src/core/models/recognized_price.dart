import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPrice extends RecognizedEntity<num> {
  RecognizedPrice({required super.line, required super.value});

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
