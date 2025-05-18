import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  Optimizer({required bool videoFeed});

  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;
  bool _isInitialized = false;

  ReceiptOptimizer({required bool videoFeed})
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

    if (receipt.isValid) {
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
