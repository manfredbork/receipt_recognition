import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer implements Optimizer {
  /// Cached receipt to optimize from.
  final CachedReceipt _cachedReceipt;

  /// Constructor to create an instance of [ReceiptOptimizer].
  ReceiptOptimizer({required videoFeed})
    : _cachedReceipt =
          videoFeed
              ? CachedReceipt.fromVideoFeed()
              : CachedReceipt.fromImages();

  /// Initializes optimizer.
  @override
  void init() {
    _cachedReceipt.clear();
  }

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    // _cachedReceipt.apply(receipt);
    _cachedReceipt.merge();

    if (kDebugMode) {
      if (_cachedReceipt.receipt.positions.isNotEmpty) {
        print('####################################');
      }
      for (final position in _cachedReceipt.receipt.positions) {
        print(
          '${position.product.value} ${position.price.formattedValue} ${position.trustworthiness}',
        );
      }
    }
    if (_cachedReceipt.receipt.positions.isNotEmpty) {
      print(_cachedReceipt.receipt.calculatedSum.formattedValue);
    }

    if (_cachedReceipt.receipt.isValid) {
      return _cachedReceipt.receipt;
    }

    return receipt;
  }

  /// Closes optimizer.
  @override
  void close() {
    init();
  }
}
