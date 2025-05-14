import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class ReceiptNormalizer {
  static RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = receipt.positions;
    return receipt.copyWith(positions: positions);
  }
}
