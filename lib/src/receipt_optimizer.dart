import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached receipts from multiple scans
  static final List<RecognizedReceipt> _cachedReceipts = [];

  /// Indicator if reinit happens
  static bool _reinit = false;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (_reinit) {
      _reinit = false;
      _cachedReceipts.clear();
    }

    _cachedReceipts.add(receipt);

    if (_cachedReceipts.length >= 10) {
      _reinit = true;
    }

    if (receipt.isValid) {
      _reinit = true;

      if (receipt.company == null) {
        for (final cachedReceipt in _cachedReceipts) {
          if (cachedReceipt.company != null) {
            return RecognizedReceipt(
              positions: receipt.positions,
              company: cachedReceipt.company,
            );
          }
        }
      }
    }

    return receipt;
  }
}
