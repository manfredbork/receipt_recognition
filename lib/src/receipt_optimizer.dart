import 'dart:collection';
import 'dart:math';

import 'package:diffutil_dart/diffutil.dart';
import 'package:flutter/foundation.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer implements Optimizer {
  /// Minimum scans required before trustworthiness is calculated.
  final int _minScansForTrustworthiness;

  /// Cached positions from multiple scans.
  final List<RecognizedPosition> _cachedPositions = [];

  /// Cached prices from multiple scans.
  final List<String> _cachedPrices = [];

  /// Cached sum from multiple scans.
  RecognizedSum? _sum;

  /// Cached company from multiple scans.
  RecognizedCompany? _company;

  /// Freeze if sum is reached from multiple scans.
  bool _freezeSum = false;

  /// Constructor to create an instance of [ReceiptOptimizer].
  ReceiptOptimizer({minScansForTrustworthiness = 3})
    : _minScansForTrustworthiness = minScansForTrustworthiness;

  /// Initializes optimizer.
  @override
  void init() {
    _cachedPositions.clear();
    _cachedPrices.clear();
    _sum = null;
    _company = null;
    _freezeSum = false;
  }

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    final mergedReceipt = _mergeReceiptFromCache(receipt);

    if (mergedReceipt.isValid) {
      if (kDebugMode) {
        if (mergedReceipt.positions.isNotEmpty) {
          print('*************************** RECEIPT ***************************');
          print('Store is ${mergedReceipt.company ?? "unknown"}');
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
    _addPricesToCache(receipt.positions);

    final updatedPositions = _updateValueAliases(receipt.positions);
    final updatedReceipt = RecognizedReceipt(
      positions: updatedPositions,
      sum: _sum,
      company: _company,
    );

    if (updatedReceipt.isValid) {
      return updatedReceipt;
    }

    if (_sumFromCache() == _sum?.value) {
      final mergedPositions = _mergePositionsFromCache();
      final mergedReceipt = RecognizedReceipt(
        positions: mergedPositions,
        sum: _sum,
        company: _company,
      );

      if (mergedReceipt.isValid) {
        return mergedReceipt;
      }
    }

    return receipt;
  }

  /// Checks if a long receipt is scanned.
  bool _isLongReceipt() {
    return _freezeSum && _cachedPrices.length >= 20;
  }

  /// Adds up sum from cache.
  num _sumFromCache() {
    return _cachedPrices.fold(0.0, (a, b) => a + num.parse(b));
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
    final sum = _sum?.value;

    if (!_freezeSum) {
      final prices = List<String>.from(
        positions.map((p) => p.price.formattedValue),
      );

      final diffResult = calculateListDiff<String>(_cachedPrices, prices);

      final updates = diffResult.getUpdatesWithData();

      for (final update in updates) {
        update.when(
          insert: (pos, data) => _cachedPrices.insert(pos, data),
          remove: (pos, data) => null,
          change: (pos, oldData, newData) => null,
          move: (from, to, data) => null,
        );
      }

      if (sum == _sumFromCache()) {
        _freezeSum = true;
      } else if (sum != null && sum < _sumFromCache()) {
        final rnd = Random();
        if (rnd.nextInt(10) == 0) {
          init();
        } else {
          _cachedPrices.clear();
        }
      }
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
          _cachedPositions[pos].price.addValueAlias(newData.price.value);
          _cachedPositions[pos].price.calculateTrustworthiness();
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
      final cachedPositions = _cachedPositions.where(
        (p) => p.isSimilar(position),
      );

      if (cachedPositions.isNotEmpty) {
        final cachedPosition =
            cachedPositions
                .where((p) => p.price.value == position.price.value)
                .firstOrNull ??
            cachedPositions.first;

        position.product.updateValueAliases(
          List.from(cachedPosition.product.valueAliases),
        );
        position.price.updateValueAliases(
          List.from(cachedPosition.price.valueAliases),
        );
      }

      if (_isLongReceipt() ||
          position.product.valueAliases.length >= _minScansForTrustworthiness) {
        position.product.calculateTrustworthiness();
      }

      if (_isLongReceipt() ||
          position.price.valueAliases.length >= _minScansForTrustworthiness) {
        position.price.calculateTrustworthiness();
      }

      updatedPositions.add(position);
    }

    return updatedPositions;
  }

  /// Merges positions from cache. Returns a list of [RecognizedPosition].
  List<RecognizedPosition> _mergePositionsFromCache() {
    final List<RecognizedPosition> mergedPositions = [];

    for (final price in _cachedPrices) {
      List<RecognizedPosition> positionCandidates =
          List<RecognizedPosition>.from(
            _cachedPositions.where((p) => p.price.formattedValue == price),
          );

      if (positionCandidates.isNotEmpty) {
        mergedPositions.add(positionCandidates.first);
      } else {
        positionCandidates = List<RecognizedPosition>.from(
          _cachedPositions.where(
            (p) => Formatter.format(p.price.value) == price,
          ),
        );
        if (positionCandidates.isNotEmpty) {
          positionCandidates.first.product.updateValueAliases([price]);
          positionCandidates.first.product.calculateTrustworthiness();
          mergedPositions.add(positionCandidates.first);
        }
      }
    }

    return mergedPositions;
  }
}
