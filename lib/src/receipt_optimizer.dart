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

    if (_cachedReceipt.isCorrectSum && _cachedReceipt.areMinScansReached) {
      _cachedReceipt.isValid = true;
    }

    return _cachedReceipt.receipt;
  }

  @override
  void close() {
    _cachedReceipt.clear();
    _init = false;
  }
}
