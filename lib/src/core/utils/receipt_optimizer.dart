import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  List<String> possibleValues(RecognizedProduct product);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedReceipt> _cachedReceipts = [];
  RecognizedReceipt? _currentMergedReceipt;
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
      _currentMergedReceipt = null;
      _shouldInitialize = false;
    }

    if (_cachedReceipts.length >= _maxCacheSize) {
      _cachedReceipts.removeAt(0);
    }
    _cachedReceipts.add(receipt);

    if (_currentMergedReceipt == null) {
      _currentMergedReceipt = receipt;
      return receipt;
    }

    _currentMergedReceipt = _mergeReceipts(_currentMergedReceipt!, receipt);

    _markNewPositions(_currentMergedReceipt!, receipt);

    return _currentMergedReceipt!;
  }

  RecognizedReceipt _mergeReceipts(
    RecognizedReceipt existing,
    RecognizedReceipt newPart,
  ) {
    final allPositions = <RecognizedPosition>[];

    for (final position in existing.positions) {
      if (!_hasNearDuplicate(position, newPart.positions)) {
        allPositions.add(position);
      }
    }

    allPositions.addAll(newPart.positions);

    final company = newPart.company ?? existing.company;
    final sum = _determineBestSum(existing.sum, newPart.sum);

    return RecognizedReceipt(
      positions: allPositions,
      company: company,
      sum: sum,
      timestamp: DateTime.now(),
    );
  }

  void _markNewPositions(
    RecognizedReceipt mergedReceipt,
    RecognizedReceipt newPart,
  ) {
    for (final position in mergedReceipt.positions) {
      for (final newPosition in newPart.positions) {
        final similarity = ratio(
          position.product.formattedValue,
          newPosition.product.formattedValue,
        );

        if (similarity >= _similarityThreshold) {
          position.operation = Operation.added;
          break;
        }
      }
    }
  }

  bool _hasNearDuplicate(
    RecognizedPosition position,
    List<RecognizedPosition> positions,
  ) {
    for (final other in positions) {
      final similarity = ratio(
        position.product.formattedValue,
        other.product.formattedValue,
      );
      if (similarity >= _similarityThreshold) {
        return true;
      }
    }
    return false;
  }

  RecognizedSum? _determineBestSum(RecognizedSum? sum1, RecognizedSum? sum2) {
    if (sum1 == null) return sum2;
    if (sum2 == null) return sum1;
    return sum1;
  }

  @override
  List<String> possibleValues(RecognizedProduct product) {
    final List<String> candidates = [];
    for (final receipt in _cachedReceipts) {
      for (final position in receipt.positions) {
        final similarity = ratio(
          product.formattedValue,
          position.product.formattedValue,
        );
        if (similarity >= _similarityThreshold) {
          candidates.add(position.product.formattedValue);
        }
      }
    }
    return candidates;
  }

  @override
  void close() {
    _cachedReceipts.clear();
    _currentMergedReceipt = null;
    _shouldInitialize = false;
  }
}
