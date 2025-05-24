import 'package:receipt_recognition/receipt_recognition.dart';

/// An interface for post-processing scanned receipts to improve accuracy.
///
/// Implementations can handle multi-frame consolidation, filtering,
/// ranking, and ordering of recognized items.
abstract class Optimizer {
  /// Initializes the optimizer before use.
  void init();

  /// Optimizes the given [RecognizedReceipt] by applying grouping,
  /// deduplication, ordering, or validation logic.
  RecognizedReceipt optimize(RecognizedReceipt receipt);

  /// Frees any cached memory or intermediate data.
  void close();
}

/// Default implementation of [Optimizer] using [CachedReceipt].
final class ReceiptOptimizer implements Optimizer {
  bool _isInitialized = false;

  @override
  void init() {
    _isInitialized = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_isInitialized) {
      _isInitialized = false;
    }

    return receipt;
  }

  @override
  void close() {
    _isInitialized = false;
  }
}
