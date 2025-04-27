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
      _cachedReceipts.clear();
      _reinit = false;
    }

    if (receipt.isValid) {
      _reinit = true;
    }

    return receipt;
  }
}
