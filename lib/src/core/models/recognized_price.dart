import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPrice extends RecognizedEntity<num> {
  int confidence;
  RecognizedPosition? position;

  RecognizedPrice({
    required super.line,
    required super.value,
    this.confidence = 0,
    this.position,
  });

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
