import 'package:receipt_recognition/receipt_recognition.dart';

abstract class Optimizer {
  void init();

  RecognizedReceipt optimize(RecognizedReceipt receipt);

  void close();
}

final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedGroup> _groups = [];
  final List<RecognizedCompany> _companies = [];
  final List<RecognizedSum> _sums = [];
  final int _maxCacheSize;
  final int _confidenceThreshold;
  final int _stabilityThreshold;
  final Duration _invalidateInterval;

  bool _shouldInitialize;

  ReceiptOptimizer({
    int maxCacheSize = 20,
    int confidenceThreshold = 75,
    int stabilityThreshold = 75,
    Duration invalidateInterval = const Duration(seconds: 2),
  }) : _maxCacheSize = maxCacheSize,
       _confidenceThreshold = confidenceThreshold,
       _stabilityThreshold = stabilityThreshold,
       _invalidateInterval = invalidateInterval,
       _shouldInitialize = false;

  @override
  void init() {
    _shouldInitialize = true;
  }

  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (_shouldInitialize) {
      _groups.clear();
      _companies.clear();
      _sums.clear();
      _shouldInitialize = false;
    }

    if (receipt.company != null) {
      _companies.add(receipt.company!);
    }

    if (_companies.length > _maxCacheSize) {
      _companies.removeAt(0);
    }

    if (receipt.sum != null) {
      _sums.add(receipt.sum!);
    }

    if (_sums.length > _maxCacheSize) {
      _sums.removeAt(0);
    }

    if (receipt.company == null && _companies.isNotEmpty) {
      final company = ReceiptNormalizer.sortByFrequency(
        _companies.map((c) => c.value).toList(),
      );
      receipt.company = _companies.last.copyWith(value: company.last);
    }

    if (receipt.sum == null && _sums.isNotEmpty) {
      final sum = ReceiptNormalizer.sortByFrequency(
        _sums.map((c) => c.formattedValue).toList(),
      );
      receipt.sum = _sums.last.copyWith(
        value: ReceiptFormatter.parse(sum.last),
      );
    }

    if (_groups.length >= _maxCacheSize) {
      DateTime now = DateTime.now();
      _groups.removeWhere(
        (g) =>
            now.difference(g.timestamp) >= _invalidateInterval &&
            g.stability < _stabilityThreshold,
      );
    }

    for (final position in receipt.positions) {
      int bestConfidence = 0;
      RecognizedGroup? bestGroup;
      for (final group in _groups) {
        final int productConfidence = group.calculateProductConfidence(
          position.product,
        );
        final int priceConfidence = group.calculatePriceConfidence(
          position.price,
        );
        final int confidence =
            ((4 * productConfidence + priceConfidence) / 5).toInt();
        final bool sameTimestamp = group.members.any(
          (p) => position.timestamp == p.timestamp,
        );
        if (!sameTimestamp &&
            confidence >= _confidenceThreshold &&
            confidence > bestConfidence) {
          bestConfidence = confidence;
          bestGroup = group;
          position.product.confidence = productConfidence;
          position.price.confidence = priceConfidence;
        }
      }
      if (bestGroup == null) {
        final newGroup = RecognizedGroup(maxGroupSize: _maxCacheSize);
        position.group = newGroup;
        newGroup.addMember(position);
        _groups.add(newGroup);
      } else {
        position.group = bestGroup;
        bestGroup.addMember(position);
      }
    }

    final stableGroups = _groups.where(
      (g) => g.stability >= _stabilityThreshold,
    );

    if (stableGroups.isEmpty || receipt.isValid) {
      return receipt;
    }

    final RecognizedReceipt mergedReceipt = RecognizedReceipt.empty();
    for (final group in stableGroups) {
      final position = group.members.reduce(
        (a, b) => a.confidence > b.confidence ? a : b,
      );
      mergedReceipt.positions.add(position);
      if (mergedReceipt.isValid) break;
    }

    return receipt.copyWith(positions: mergedReceipt.positions);
  }

  @override
  void close() {
    _groups.clear();
    _companies.clear();
    _sums.clear();
    _shouldInitialize = false;
  }
}
