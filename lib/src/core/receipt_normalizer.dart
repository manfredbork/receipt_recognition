import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class ReceiptNormalizer {
  static RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      positions.add(position.group.mostTrustworthyPosition(position));
    }

    positions.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return receipt.copyWith(positions: positions);
  }
}
