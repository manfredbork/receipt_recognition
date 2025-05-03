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

      if (kDebugMode) {
        if (mergedReceipt.positions.isNotEmpty) {
          print('***************************');
        }
        for (final position in mergedReceipt.positions) {
          print(
            '${position.product.formattedValue} ${position.price.formattedValue} ${position.product.valueAliases} Credibility ${position.product.credibility}%',
          );
        }
        if (mergedReceipt.positions.isNotEmpty) {
          print(
            'Calculated sum is ${mergedReceipt.calculatedSum.formattedValue}',
          );
          print('Receipt sum is ${mergedReceipt.sum?.formattedValue}');
        }
      }

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
    writeSumToCache(receipt.sum);
    writeCompanyToCache(receipt.company);
    addPositionsToCache(receipt.positions);

    final updatedPositions = updateValueAliases(receipt.positions);
    final updatedReceipt = RecognizedReceipt(
      positions: updatedPositions,
      sum: _sum,
      company: _company,
    );

    if (updatedReceipt.isValid) {
      return updatedReceipt;
    }

    final mergedPositions = mergePositionsFromCache();
    final mergedReceipt = RecognizedReceipt(
      positions: mergedPositions,
      sum: _sum,
      company: _company,
    );

    return mergedReceipt;
  }

  /// Writes sum to cache.
  static void writeSumToCache(RecognizedSum? sum) {
    _sum = sum ?? _sum;
  }

  /// Writes company to cache.
  static void writeCompanyToCache(RecognizedCompany? company) {
    _company = company ?? _company;
  }

  /// Adds and updates positions to cache.
  static void addPositionsToCache(List<RecognizedPosition> positions) {
    for (final position in positions) {
      final index = _cachedPositions.indexWhere(
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
  }

  /// Updates value aliases. Returns a list of [RecognizedPosition].
  static List<RecognizedPosition> updateValueAliases(
    List<RecognizedPosition> positions,
  ) {
    List<RecognizedPosition> updatedPositions = [];

    for (final position in positions) {
      final index = _cachedPositions.indexWhere(
        (p) =>
            p.product.isSimilar(position.product) &&
            p.price.formattedValue == position.price.formattedValue,
      );

      if (index >= 0) {
        position.product.updateAllValueAliases(
          List.from(_cachedPositions[index].product.valueAliases),
        );
      }

      updatedPositions.add(position);
    }

    return updatedPositions;
  }

  /// Merges positions from cache. Returns a list of [RecognizedPosition].
  static List<RecognizedPosition> mergePositionsFromCache() {
    List<RecognizedPosition> mergedPositions = [];

    for (final position in _cachedPositions) {
      // TODO: Merge positions from cache
      position;
    }

    return mergedPositions;
  }
}
