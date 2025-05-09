import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

class ReceiptOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;

  ReceiptOptimizer({required videoFeed})
    : _cachedReceipt =
          videoFeed
              ? CachedReceipt.fromVideoFeed()
              : CachedReceipt.fromImages();

  @override
  void init() {
    _cachedReceipt.clear();
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    _cachedReceipt.apply(receipt);
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

  @override
  void close() {
    init();
  }
}
