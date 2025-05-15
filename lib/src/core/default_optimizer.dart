import 'cached_receipt.dart';
import 'optimizer_interface.dart';
import 'receipt_normalizer.dart';
import 'recognized_receipt.dart';

final class DefaultOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;
  bool _isInitialized = false;

  DefaultOptimizer({required bool videoFeed})
    : _cachedReceipt = CachedReceipt(
        positions: [],
        timestamp: DateTime.now(),
        videoFeed: videoFeed,
        positionGroups: [],
      );

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

    if (receipt.isValid &&
        (receipt.isSufficientlyScanned || receipt.isLongReceipt)) {
      return ReceiptNormalizer.normalize(receipt);
    }

    return ReceiptNormalizer.normalize(_cachedReceipt);
  }

  @override
  void close() {
    _cachedReceipt.clear();
    _isInitialized = false;
  }
}
