import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition by multiple scans of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached receipts from multiple scans
  final List<RecognizedReceipt> _cachedReceipts;

  /// Indicator if reinit happens
  bool _reinit = false;

  /// Constructor to create an instance of [ReceiptRecognizer].
  ReceiptOptimizer() : _cachedReceipts = [];

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
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
