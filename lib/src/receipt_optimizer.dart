import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached receipt
  static RecognizedReceipt? _cachedReceipt;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (receipt.isValid) {
      _cachedReceipt = null;
      return receipt;
    }

    final mergedReceipt = mergeReceipts(receipt);

    if (mergedReceipt.isValid) {
      _cachedReceipt = null;
      return mergedReceipt;
    }

    _cachedReceipt = mergedReceipt;

    return receipt;
  }

  /// Merges with cached [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt mergeReceipts(RecognizedReceipt receipt) {
    final List<RecognizedPosition> mergedPositions =
        _cachedReceipt?.positions ?? [];

    if (mergedPositions == receipt.positions) return receipt;

    for (final position in receipt.positions) {
      if (!mergedPositions.any((p) => p.hashCode == position.hashCode)) {
        mergedPositions.add(position);
      }
    }

    final mergedReceipt = RecognizedReceipt(
      positions: mergedPositions,
      sum: receipt.sum ?? _cachedReceipt?.sum,
      company: receipt.company ?? _cachedReceipt?.company,
    );

    final sum = mergedReceipt.sum;

    if (sum != null && sum.value < mergedReceipt.calculatedSum.value) {
      return RecognizedReceipt(
        positions: [],
        sum: mergedReceipt.sum,
        company: mergedReceipt.company,
      );
    }

    return mergedReceipt;
  }
}
