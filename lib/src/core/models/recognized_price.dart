import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedPrice extends RecognizedEntity<num> {
  final int confidence;

  RecognizedPosition? position;

  RecognizedPrice({
    required super.line,
    required super.value,
    this.confidence = 100,
    this.position,
  });

  @override
  String format(num value) => ReceiptFormatter.format(value);
}
