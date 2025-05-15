import 'recognized_position.dart';
import 'recognized_receipt.dart';

final class ReceiptNormalizer {
  static RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final List<RecognizedPosition> positions = [];

    for (final position in receipt.positions) {
      final mostTrustworthy = position.group.mostTrustworthyPosition(position);

      positions.add(mostTrustworthy);
    }

    positions.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    return receipt.copyWith(positions: positions);
  }
}
