import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer implements Optimizer {
  /// Minimum scans required before trustworthiness is calculated
  final int _minScansForTrustworthiness;

  /// Cached positions from multiple scans
  final List<RecognizedPosition> _cachedPositions = [];

  /// Cached sum from multiple scans
  RecognizedSum? _sum;

  /// Cached company from multiple scans
  RecognizedCompany? _company;

  /// Constructor to create an instance of [ReceiptOptimizer].
  ReceiptOptimizer({minScansForTrustworthiness = 3})
    : _minScansForTrustworthiness = minScansForTrustworthiness;

  /// Initializes optimizer.
  @override
  void init() {
    _cachedPositions.clear();
    _sum = null;
    _company = null;
  }

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    final mergedReceipt = _mergeReceiptFromCache(receipt);

    if (mergedReceipt.isValid) {
      if (kDebugMode) {
        if (mergedReceipt.positions.isNotEmpty) {
          print('***************************');
        }
        for (final position in mergedReceipt.positions) {
          print(
            '${position.product.formattedValue} ${position.price.formattedValue} ${position.product.valueAliases} Trustworthiness ${position.product.trustworthiness}%',
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

  /// Closes optimizer.
  @override
  void close() {
    init();
  }

  /// Merges receipt from cache. Returns a [RecognizedReceipt].
  RecognizedReceipt _mergeReceiptFromCache(RecognizedReceipt receipt) {
    _writeSumToCache(receipt.sum);
    _writeCompanyToCache(receipt.company);
    _addPositionsToCache(receipt.positions);

    final updatedPositions = _updateValueAliases(receipt.positions);
    final updatedReceipt = RecognizedReceipt(
      positions: updatedPositions,
      sum: _sum,
      company: _company,
    );

    if (updatedReceipt.isValid) {
      return updatedReceipt;
    }

    final mergedPositions = _mergePositionsFromCache();
    final mergedReceipt = RecognizedReceipt(
      positions: mergedPositions,
      sum: _sum,
      company: _company,
    );

    return mergedReceipt;
  }

  /// Writes sum to cache.
  void _writeSumToCache(RecognizedSum? sum) {
    _sum = sum ?? _sum;
  }

  /// Writes company to cache.
  void _writeCompanyToCache(RecognizedCompany? company) {
    _company = company ?? _company;
  }

  /// Adds and updates positions to cache.
  void _addPositionsToCache(List<RecognizedPosition> positions) {
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
        _cachedPositions[index].product.calculateTrustworthiness();
      }
    }
  }

  /// Updates value aliases. Returns a list of [RecognizedPosition].
  List<RecognizedPosition> _updateValueAliases(
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
        position.product.updateValueAliases(
          List.from(_cachedPositions[index].product.valueAliases),
        );
      }

      if (position.product.valueAliases.length >= _minScansForTrustworthiness) {
        position.product.calculateTrustworthiness();
      }

      updatedPositions.add(position);
    }

    return updatedPositions;
  }

  /// Merges positions from cache. Returns a list of [RecognizedPosition].
  List<RecognizedPosition> _mergePositionsFromCache() {
    List<RecognizedPosition> mergedPositions = [];

    for (final position in _cachedPositions) {
      // TODO: Merge positions from cache
      position;
    }

    return mergedPositions;
  }
}
