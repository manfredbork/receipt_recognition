import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached positions from multiple scans
  static final List<RecognizedPosition> _cachedPositions = [];

  /// Cached product values from multiple scans
  static final Map<int, List<String>> _cachedProductValues = {};

  /// Cached sum from multiple scans
  static RecognizedSum? _sum;

  /// Cached company from multiple scans
  static RecognizedCompany? _company;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    final mergedReceipt = mergeReceiptFromCache(receipt);

    if (kDebugMode) {
      if (mergedReceipt.positions.isNotEmpty) {
        print('***************************');
      }
      for (final position in mergedReceipt.positions) {
        print(
          '${position.product.value} ${position.price.formattedValue} ${position.hashCode}',
        );
      }
      if (mergedReceipt.positions.isNotEmpty) {
        print(
          '${mergedReceipt.calculatedSum.formattedValue} / ${mergedReceipt.sum?.formattedValue}',
        );
      }
    }

    if (mergedReceipt.isValid) {
      _cachedPositions.clear();
      _cachedProductValues.clear();
      _sum = null;
      _company = null;

      return mergedReceipt;
    }

    return receipt;
  }

  /// Merges receipt from cache. Returns a [RecognizedReceipt].
  static RecognizedReceipt mergeReceiptFromCache(RecognizedReceipt receipt) {
    _sum = receipt.sum ?? _sum;
    _company = receipt.company ?? _company;

    RecognizedReceipt? mergedReceipt;
    int insertIndex = 0;

    for (final position in receipt.positions) {
      final index = _cachedPositions.lastIndexWhere((p) => p == position);

      if (index >= 0) {
        insertIndex = index;
      } else if (insertIndex < _cachedPositions.length) {
        _cachedPositions.insert(insertIndex++, position);
      } else {
        _cachedPositions.add(position);
      }

      if (_cachedProductValues.containsKey(position.hashCode)) {
        _cachedProductValues[position.hashCode]?.add(position.product.value);
      } else {
        _cachedProductValues[position.hashCode] = [position.product.value];
      }

      mergedReceipt = RecognizedReceipt(
        positions: _cachedPositions,
        sum: _sum,
        company: _company,
      );

      if (mergedReceipt.isValid) {
        return mergedReceipt;
      }
    }

    if (mergedReceipt != null) {
      return mergedReceipt;
    }

    return RecognizedReceipt(
      positions: receipt.positions,
      sum: _sum,
      company: _company,
    );
  }
}
