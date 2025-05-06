import 'dart:collection';

import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer implements Optimizer {
  /// Minimum scans required before trustworthiness is calculated.
  final int _minScansForTrustworthiness;

  /// Cached prices from multiple scans.
  final List<num> _cachedPrices = [];

  /// Cached positions from multiple scans.
  final List<RecognizedPosition> _cachedPositions = [];

  /// Cached sum from multiple scans.
  RecognizedSum? _sum;

  /// Cached company from multiple scans.
  RecognizedCompany? _company;

  /// Freeze if cached sum is reached.
  bool _freezeSum = false;

  /// Constructor to create an instance of [ReceiptOptimizer].
  ReceiptOptimizer({minScansForTrustworthiness = 3})
    : _minScansForTrustworthiness = minScansForTrustworthiness;

  /// Initializes optimizer.
  @override
  void init() {
    _cachedPrices.clear();
    _cachedPositions.clear();
    _sum = null;
    _company = null;
    _freezeSum = false;
  }

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    final mergedReceipt = _mergeReceiptFromCache(receipt);

    if (kDebugMode) {
      if (mergedReceipt.positions.isNotEmpty) {
        print('***************************');
      }
      for (final position in mergedReceipt.positions) {
        print(
          'Product: ${position.product.formattedValue}, Price: ${position.price.formattedValue}, Trust: ${position.product.trustworthiness}%',
        );
      }
      if (mergedReceipt.positions.isNotEmpty) {
        print(
          'Calculated sum is ${mergedReceipt.calculatedSum.formattedValue}',
        );
        print('Receipt sum is ${mergedReceipt.sum?.formattedValue}');
      }
    }

    if (mergedReceipt.isValid) {
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

    if (!_freezeSum) {
      _addPricesToCache(receipt.positions);
    }

    final updatedPositions = _updateValueAliases(receipt.positions);
    final updatedReceipt = RecognizedReceipt(
      positions: updatedPositions,
      sum: _sum,
      company: _company,
    );

    if (updatedReceipt.isValid) {
      return updatedReceipt;
    }

    if (_isCorrectSum()) {
      final mergedPositions = _mergePositionsFromCache();
      final mergedReceipt = RecognizedReceipt(
        positions: mergedPositions,
        sum: _sum,
        company: _company,
      );

      if (mergedReceipt.isValid) {
        return mergedReceipt;
      }

      _freezeSum = true;
    }

    return receipt;
  }

  /// Checks if sum of cached prices is equal to receipt sum from cache.
  bool _isCorrectSum() {
    final sum = _cachedPrices.fold(0.0, (a, b) => a + b);

    return sum == _sum?.value;
  }

  /// Writes sum to cache.
  void _writeSumToCache(RecognizedSum? sum) {
    _sum = sum ?? _sum;
  }

  /// Writes company to cache.
  void _writeCompanyToCache(RecognizedCompany? company) {
    _company = company ?? _company;
  }

  /// Adds and updates prices to cache.
  void _addPricesToCache(List<RecognizedPosition> positions) {
    final prices = List<num>.from(positions.map((p) => p.price.value));

    final diffResult = calculateListDiff<num>(_cachedPrices, prices);

    final updates = diffResult.getUpdatesWithData();

    for (final update in updates) {
      update.when(
        insert: (pos, data) => _cachedPrices.insert(pos, data),
        remove: (pos, data) => null,
        change: (pos, oldData, newData) => null,
        move: (from, to, data) => null,
      );
    }
  }

  /// Adds and updates positions to cache.
  void _addPositionsToCache(List<RecognizedPosition> positions) {
    final diffResult = calculateDiff(
      PositionListDiff(_cachedPositions, positions),
    );

    final updates = diffResult.getUpdatesWithData();

    for (final update in updates) {
      update.when(
        insert: (pos, data) => _cachedPositions.insert(pos, data),
        remove: (pos, data) => null,
        change: (pos, oldData, newData) {
          _cachedPositions[pos].product.addValueAlias(newData.product.value);
          _cachedPositions[pos].product.calculateTrustworthiness();
        },
        move: (from, to, data) => null,
      );
    }
  }

  /// Updates value aliases. Returns a list of [RecognizedPosition].
  List<RecognizedPosition> _updateValueAliases(
    List<RecognizedPosition> positions,
  ) {
    final List<RecognizedPosition> updatedPositions = [];

    for (final position in positions) {
      final cachedPosition =
          _cachedPositions.where((p) => p.isSimilar(position)).firstOrNull;

      if (cachedPosition != null) {
        position.product.updateValueAliases(
          List.from(cachedPosition.product.valueAliases),
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
    final List<RecognizedPosition> mergedPositions = [];

    // TODO: Merge positions from cache data

    return mergedPositions;
  }
}
