import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached positions from multiple scans
  static final Map<int, RecognizedPosition> _cachedPositions = {};

  /// Cached sum from multiple scans
  static RecognizedSum? sum;

  /// Cached company from multiple scans
  static RecognizedCompany? company;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    final mergedReceipt = mergeReceiptFromCache(receipt);

    if (mergedReceipt.isValid) {
      return mergedReceipt;
    }

    return receipt;
  }

  /// Merges receipt from cache. Returns a [RecognizedReceipt].
  static RecognizedReceipt mergeReceiptFromCache(RecognizedReceipt receipt) {
    sum = receipt.sum ?? sum;
    company = receipt.company ?? company;

    return RecognizedReceipt(
      positions: receipt.positions,
      sum: sum,
      company: company,
    );
  }
}
