import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer implements Optimizer {
  /// Indicates if a video feed should be optimized.
  final bool _videoFeed;

  /// Constructor to create an instance of [ReceiptOptimizer].
  ReceiptOptimizer({videoFeed}) : _videoFeed = videoFeed;

  /// Initializes optimizer.
  @override
  void init() {
    _videoFeed;
  }

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    return receipt;
  }

  /// Closes optimizer.
  @override
  void close() {
    init();
  }
}
