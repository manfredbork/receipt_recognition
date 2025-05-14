import 'package:flutter/foundation.dart';

import 'cached_receipt.dart';
import 'optimizer_interface.dart';
import 'recognized_receipt.dart';

final class DefaultOptimizer implements Optimizer {
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

    if (receipt.isValid) {
      return _cachedReceipt.normalizeFromCache(receipt);
    }

    final cachedReceipt = _cachedReceipt.normalizedReceipt;

    if (kDebugMode) {
      if (cachedReceipt.positions.isNotEmpty) {
        print('-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_');
        for (final position in cachedReceipt.positions) {
          print(
            '${position.product.value} ${position.price.formattedValue} ${position.timestamp}',
          );
        }
        print(cachedReceipt.calculatedSum.formattedValue);
      }
    }

    return cachedReceipt.isValid ? cachedReceipt : receipt;
  }

  @override
  void close() {
    _cachedReceipt.clear();
    _isInitialized = false;
  }
}
