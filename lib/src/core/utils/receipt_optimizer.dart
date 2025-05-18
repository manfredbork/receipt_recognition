import 'package:receipt_recognition/receipt_recognition.dart';

/// An interface for post-processing scanned receipts to improve accuracy.
///
/// Implementations can handle multi-frame consolidation, filtering,
/// ranking, and ordering of recognized items.
abstract class Optimizer {
  /// Creates an [Optimizer] instance, optionally configured for video feeds.
  Optimizer({required bool videoFeed});

  /// Initializes the optimizer before use.
  void init();

  /// Optimizes the given [RecognizedReceipt] by applying grouping,
  /// deduplication, ordering, or validation logic.
  RecognizedReceipt optimize(RecognizedReceipt receipt);

  /// Frees any cached memory or intermediate data.
  void close();
}

/// Default implementation of [Optimizer] using [CachedReceipt].
///
/// Aggregates multiple scan frames and consolidates the receipt by applying
/// position grouping, graph-based ordering, and sum validation.
final class ReceiptOptimizer implements Optimizer {
  final CachedReceipt _cachedReceipt;
  bool _isInitialized = false;

  /// Creates a [ReceiptOptimizer] with an internal [CachedReceipt] state.
  ///
  /// Set [videoFeed] to `true` to require more confirmations for validity.
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
