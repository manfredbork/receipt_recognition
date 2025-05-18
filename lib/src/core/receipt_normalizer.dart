import 'package:receipt_recognition/receipt_recognition.dart';

final class ReceiptNormalizer {
  static RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      positions.add(position);
    }

    return receipt.copyWith(positions: positions);
  }
}
