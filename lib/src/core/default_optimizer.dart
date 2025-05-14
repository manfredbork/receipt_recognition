import 'package:flutter/foundation.dart';

import 'cached_receipt.dart';
import 'optimizer_interface.dart';
import 'recognized_receipt.dart';

class DefaultOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;
  bool _isInitialized = false;

  DefaultOptimizer({required bool videoFeed})
    : _cachedReceipt =
          videoFeed
              ? CachedReceipt.fromVideoFeed()
              : CachedReceipt.fromImages();

  @override
  void init() {
    _isInitialized = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_isInitialized) {
      _cachedReceipt.clear();
      _isInitialized = false;
    }

    _cachedReceipt.apply(receipt);
    _cachedReceipt.consolidatePositions();
    _cachedReceipt.validate(receipt);

    if (receipt.isValid) {
      return _cachedReceipt.normalize(receipt);
    }

    final cachedReceipt = _cachedReceipt.receipt;

    _cachedReceipt.validate(cachedReceipt);

    if (kDebugMode) {
      final debugReceipt = _cachedReceipt.normalize(cachedReceipt);
      if (debugReceipt.positions.isNotEmpty) {
        print('-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_');
        for (final position in debugReceipt.positions) {
          print(
            '${position.product.value} ${position.price.formattedValue} ${position.trustworthiness} ${position.group.timestamp}',
          );
        }
        print(debugReceipt.calculatedSum.formattedValue);
      }
    }

    return cachedReceipt.isValid
        ? _cachedReceipt.normalize(cachedReceipt)
        : receipt;
  }

  @override
  void close() {
    _cachedReceipt.clear();
    _isInitialized = false;
  }
}
