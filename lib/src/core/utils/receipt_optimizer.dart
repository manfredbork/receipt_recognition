import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  List<String> possibleProductValues(RecognizedProduct product);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedReceipt> _cachedReceipts = [];
  final int _maxCacheSize;
  final int _similarityThreshold;
  bool _shouldInitialize;

  ReceiptOptimizer({int maxCacheSize = 20, int similarityThreshold = 75})
    : _maxCacheSize = maxCacheSize,
      _similarityThreshold = similarityThreshold,
      _shouldInitialize = false;

  @override
  void init() {
    _shouldInitialize = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_shouldInitialize) {
      _cachedReceipts.clear();
      _shouldInitialize = false;
    }

    if (_cachedReceipts.isNotEmpty) {
      receipt.company ??= _cachedReceipts.last.company;
      receipt.sum ??= _cachedReceipts.last.sum;
    }

    if (_cachedReceipts.length >= _maxCacheSize) {
      _cachedReceipts.removeAt(0);
    }

    _cachedReceipts.add(receipt);

    return receipt;
  }

  @override
  List<String> possibleProductValues(RecognizedProduct product) {
    final List<String> candidates = [];
    for (final receipt in _cachedReceipts) {
      for (final position in receipt.positions) {
        if (position.product.formattedValue == product.formattedValue) {
          final similarity = ratio(
            product.formattedValue,
            position.product.formattedValue,
          );
          if (similarity >= _similarityThreshold) {
            candidates.add(position.product.formattedValue);
          }
        }
      }
    }
    return candidates;
  }

  @override
  void close() {
    _cachedReceipts.clear();
    _shouldInitialize = false;
  }
}
