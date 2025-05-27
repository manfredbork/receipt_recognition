import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void assignAlternativeTexts(RecognizedReceipt receipt);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedReceipt> _cachedReceipts = [];
  final int _maxCacheSize;
  final int _similarityThreshold;
  bool _shouldInitialize;

  ReceiptOptimizer({int maxCacheSize = 20, int similarityThreshold = 50})
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
  void assignAlternativeTexts(RecognizedReceipt receipt) {
    for (final position in receipt.positions) {
      final List<String> alternativeTexts = [];
      for (final cachedReceipt in _cachedReceipts) {
        final texts = cachedReceipt.positions
            .where((p) {
              if (p.price.formattedValue == position.price.formattedValue) {
                final similarity = ratio(
                  p.product.formattedValue,
                  position.product.formattedValue,
                );
                return similarity >= _similarityThreshold;
              }
              return false;
            })
            .map((p) => p.product.text);
        alternativeTexts.addAll(texts);
      }
      position.product.alternativeTexts.clear();
      position.product.alternativeTexts.addAll(alternativeTexts);
    }
  }

  @override
  void close() {
    _cachedReceipts.clear();
    _shouldInitialize = false;
  }
}
