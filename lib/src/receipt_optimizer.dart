import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Initializes cached variables if true
  static bool _init = false;

  /// Cached positions from multiple scans
  static final List<RecognizedPosition> _cachedPositions = [];

  /// Cached sum from multiple scans
  static RecognizedSum? _sum;

  /// Cached company from multiple scans
  static RecognizedCompany? _company;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (_init == true) {
      _cachedPositions.clear();
      _sum = null;
      _company = null;
      _init = false;
    }

    final mergedReceipt = mergeReceiptFromCache(receipt);

    if (mergedReceipt.isValid) {
      _init = true;
      return mergedReceipt;
    }

    return receipt;
  }

  /// Initializes cached variables on next optimization call.
  static void init() {
    _init = true;
  }

  /// Merges receipt from cache. Returns a [RecognizedReceipt].
  static RecognizedReceipt mergeReceiptFromCache(RecognizedReceipt receipt) {
    _sum = receipt.sum ?? _sum;
    _company = receipt.company ?? _company;

    RecognizedReceipt? mergedReceipt;

    int index = 0;

    for (final position in receipt.positions) {
      index = _cachedPositions.indexWhere(
        (p) =>
            p.product.isSimilar(position.product) &&
            p.price.formattedValue == position.price.formattedValue,
      );

      if (index == -1) {
        _cachedPositions.add(position);
      } else {
        _cachedPositions[index].product.addValueAlias(position.product.value);
      }
    }

    mergedReceipt = RecognizedReceipt(
      positions: _cachedPositions,
      sum: _sum,
      company: _company,
    );

    if (mergedReceipt.isValid) {
      return mergedReceipt;
    }

    if (kDebugMode) {
      if (_cachedPositions.isNotEmpty) {
        print('***************************');
      }
      for (final position in _cachedPositions) {
        print(
          '${position.product.formattedValue} ${position.price.formattedValue} ${position.product.valueAliases}',
        );
      }
      if (_cachedPositions.isNotEmpty) {
        print(
          '${mergedReceipt.calculatedSum.formattedValue} / ${mergedReceipt.sum?.formattedValue}',
        );
      }
    }

    return RecognizedReceipt(
      positions: _cachedPositions,
      sum: _sum,
      company: _company,
    );
  }
}
