import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

class ReceiptOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;

  bool _init;

  ReceiptOptimizer({required videoFeed})
    : _cachedReceipt =
          videoFeed
              ? CachedReceipt.fromVideoFeed()
              : CachedReceipt.fromImages(),
      _init = false;

  @override
  void init() {
    _init = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_init == true) {
      _cachedReceipt.clear();
      _init = false;
    }

    _cachedReceipt.apply(receipt);
    _cachedReceipt.merge();
    _cachedReceipt.validate(receipt);

    if (receipt.isValid) {
      return _cachedReceipt.normalize(receipt);
    }

    final cachedReceipt = _cachedReceipt.receipt;

    _cachedReceipt.validate(cachedReceipt);

    if (kDebugMode) {
      if (cachedReceipt.positions.isNotEmpty) {
        print('####################################');
      }
      for (final position in cachedReceipt.positions) {
        print(
          '${position.product.value} ${position.price.formattedValue} ${position.trustworthiness}',
        );
      }
      if (cachedReceipt.positions.isNotEmpty) {
        print(cachedReceipt.calculatedSum.formattedValue);
      }
    }

    if (cachedReceipt.isValid) {
      return _cachedReceipt.normalize(cachedReceipt);
    }

    return receipt;
  }

  @override
  void close() {
    _cachedReceipt.clear();
    _init = false;
  }
}
