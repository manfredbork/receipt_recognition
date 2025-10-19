import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/logging/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Interface for receipt optimization components.
abstract class Optimizer {
  /// Initializes or resets the optimizer state.
  void init();

  /// Processes a receipt and returns an optimized version.
  ///
  /// Set [test] to true to always return a merged/optimized receipt.
  RecognizedReceipt optimize(
    RecognizedReceipt receipt,
    ReceiptOptions options, {
    bool test = false,
  });

  /// Releases resources used by the optimizer.
  void close();
}

/// Default implementation of receipt optimizer that uses confidence scoring and grouping.
final class ReceiptOptimizer implements Optimizer {
  /// Working position groups.
  final List<RecognizedGroup> _groups = [];

  /// Cache of stores from recent frames.
  final List<RecognizedStore> _stores = [];

  /// Cache of totals from recent frames.
  final List<RecognizedTotal> _totals = [];

  /// Cache of total labels from recent frames.
  final List<RecognizedTotalLabel> _totalLabels = [];

  /// Cache of purchase dates from recent frames.
  final List<RecognizedPurchaseDate> _purchaseDates = [];

  /// Ordering stats by group.
  final Map<RecognizedGroup, _OrderStats> _orderStats = {};

  /// Shorthand for the active options provided by [ReceiptRuntime].
  final ReceiptOptions _opts = ReceiptRuntime.options;

  /// Internal convergence bookkeeping.
  int _unchangedCount = 0;

  /// Whether a full reinit is needed.
  bool _shouldInitialize = false;

  /// Whether we should force a regroup step.
  bool _needsRegrouping = false;

  /// Last fingerprint to detect stalling.
  String? _lastFingerprint;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() => _shouldInitialize = true;

  /// Processes a receipt and returns an optimized version driven by [options] tuning.
  @override
  RecognizedReceipt optimize(
    RecognizedReceipt receipt,
    ReceiptOptions options, {
    bool test = false,
  }) {
    return ReceiptRuntime.runWithOptions(options, () {
      _initializeIfNeeded();
      _checkConvergence(receipt);
      _updateStores(receipt);
      _updateTotals(receipt);
      _updateTotalLabels(receipt);
      _updatePurchaseDates(receipt);
      _optimizeStore(receipt);
      _optimizeTotal(receipt);
      _optimizeTotalLabel(receipt);
      _optimizePurchaseDate(receipt);
      _cleanupGroups();
      _resetOperations();
      _processPositions(receipt);
      _reconcileToTotal(receipt);
      _updateEntities(receipt);
      return _createOptimizedReceipt(receipt, test: test);
    });
  }

  /// Releases all resources used by the optimizer.
  @override
  void close() {
    _shouldInitialize = true;
    _initializeIfNeeded();
  }

  /// Clears caches and resets internal state if flagged.
  void _initializeIfNeeded() {
    if (!_shouldInitialize) return;
    _groups.clear();
    _stores.clear();
    _totals.clear();
    _totalLabels.clear();
    _purchaseDates.clear();
    _orderStats.clear();
    _shouldInitialize = false;
    _needsRegrouping = false;
    _unchangedCount = 0;
    _lastFingerprint = null;
  }

  /// Tracks convergence to avoid infinite loops and trigger regrouping.
  void _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.normalizedText}:${p.price.value}')
        .join(',');
    final totalHash = receipt.total?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$totalHash';

    final loopThreshold = _opts.tuning.optimizerLoopThreshold;

    if (_lastFingerprint == fingerprint) {
      _unchangedCount++;
      if (_unchangedCount == (loopThreshold ~/ 2)) _needsRegrouping = true;
      if (_unchangedCount >= loopThreshold) return;
    } else {
      _unchangedCount = 0;
    }
    _lastFingerprint = fingerprint;
  }

  /// Forces regrouping of all positions into fresh groups.
  void _forceRegroup() {
    final allPositions = _groups.expand((g) => g.members).toList();
    _groups.clear();
    for (final position in allPositions) {
      _processPosition(position);
    }
  }

  /// Updates store history cache for later normalization.
  void _updateStores(RecognizedReceipt receipt) {
    final store = receipt.store;
    if (store != null) _stores.add(store);
    _trimCache(_stores);
  }

  /// Updates totals history cache for later normalization.
  void _updateTotals(RecognizedReceipt receipt) {
    final total = receipt.total;
    if (total != null) _totals.add(total);
    _trimCache(_totals);
  }

  /// Updates total labels history cache for later normalization.
  void _updateTotalLabels(RecognizedReceipt receipt) {
    final totalLabel = receipt.totalLabel;
    if (totalLabel != null) _totalLabels.add(totalLabel);
    _trimCache(_totalLabels);
  }

  /// Updates purchase dates history cache for later normalization.
  void _updatePurchaseDates(RecognizedReceipt receipt) {
    final purchaseDate = receipt.purchaseDate;
    if (purchaseDate != null) _purchaseDates.add(purchaseDate);
    _trimCache(_purchaseDates);
  }

  /// Trims a cache list to the configured precision size.
  void _trimCache(List list) {
    final maxCacheSize = _opts.tuning.optimizerMaxCacheSize;
    while (list.length > maxCacheSize) {
      list.removeAt(0);
    }
  }

  /// Fills store with the most frequent value in history.
  void _optimizeStore(RecognizedReceipt receipt) {
    if (_stores.isEmpty) return;
    final mostFrequentStore = ReceiptNormalizer.sortByFrequency(
      _stores.map((c) => c.value).toList(),
    );
    if (_stores.last.value == mostFrequentStore.last) {
      receipt.store = _stores.last;
    } else {
      final store = _stores.lastWhere((s) => s.value == mostFrequentStore.last);
      receipt.store = store.copyWith(
        line: ReceiptTextLine(text: store.line.text),
      );
    }
  }

  /// Fills total label with the most frequent value in history.
  void _optimizeTotalLabel(RecognizedReceipt receipt) {
    if (_totalLabels.isEmpty) return;
    final mostFrequentTotalLabel = ReceiptNormalizer.sortByFrequency(
      _totalLabels.map((c) => c.value).toList(),
    );
    if (_totalLabels.last.value == mostFrequentTotalLabel.last) {
      receipt.totalLabel = _totalLabels.last;
    } else {
      final totalLabel = _totalLabels.lastWhere(
        (s) => s.value == mostFrequentTotalLabel.last,
      );
      receipt.totalLabel = totalLabel.copyWith(
        line: ReceiptTextLine(text: totalLabel.line.text),
      );
    }
  }

  /// Fills total with the most frequent value in history.
  void _optimizeTotal(RecognizedReceipt receipt) {
    if (_totals.isEmpty) return;
    final mostFrequentTotal = ReceiptNormalizer.sortByFrequency(
      _totals.map((c) => c.formattedValue).toList(),
    );
    if (_totals.last.formattedValue == mostFrequentTotal.last) {
      receipt.total = _totals.last;
    } else {
      final total = _totals.lastWhere(
        (s) => s.formattedValue == mostFrequentTotal.last,
      );
      receipt.total = total.copyWith(
        line: ReceiptTextLine(text: total.line.text),
      );
    }
  }

  /// Fills purchase date with the most frequent value in history.
  void _optimizePurchaseDate(RecognizedReceipt receipt) {
    if (_purchaseDates.isEmpty) return;
    final mostFrequentPurchaseDate = ReceiptNormalizer.sortByFrequency(
      _purchaseDates.map((c) => c.formattedValue).toList(),
    );
    if (_purchaseDates.last.formattedValue == mostFrequentPurchaseDate.last) {
      receipt.purchaseDate = _purchaseDates.last;
    } else {
      final purchaseDate = _purchaseDates.lastWhere(
        (s) => s.formattedValue == mostFrequentPurchaseDate.last,
      );
      receipt.purchaseDate = purchaseDate.copyWith(
        line: ReceiptTextLine(text: purchaseDate.line.text),
      );
    }
  }

  /// Removes empty groups and very early weak outliers based on grace/thresholds.
  void _cleanupGroups() {
    final now = DateTime.now();
    final emptied = _groups.where((g) => g.members.isEmpty).toList();
    if (emptied.isNotEmpty) {
      for (final g in emptied) {
        ReceiptLogger.log('group.empty', {'grp': ReceiptLogger.grpKey(g)});
      }
      _purgeGroups(emptied.toSet());
    }

    final earlyOutliers =
        _groups.where((g) => _isEarlyOutlier(g, now)).toList();
    if (earlyOutliers.isNotEmpty) _purgeGroups(earlyOutliers.toSet());
  }

  /// Resets per-frame operation markers on positions.
  void _resetOperations() {
    for (final group in _groups) {
      for (final position in group.members) {
        position.operation = Operation.none;
      }
    }
  }

  /// Processes and assigns all receipt positions to groups; forces a full regroup if flagged.
  void _processPositions(RecognizedReceipt receipt) {
    for (final position in receipt.positions) {
      _processPosition(position);
    }

    if (_needsRegrouping) {
      _forceRegroup();
      _needsRegrouping = false;
    }
  }

  /// Assigns a position to the best existing group or creates a new one.
  void _processPosition(RecognizedPosition position) {
    int bestConfidence = 0;
    RecognizedGroup? bestGroup;

    for (final group in _groups) {
      final result = _calculateConfidence(position, group, bestConfidence);
      if (result.shouldUseGroup) {
        bestConfidence = result.confidence;
        bestGroup = group;
        position.product.confidence = result.productConfidence;
        position.price.confidence = result.priceConfidence;
      }
    }

    if (bestGroup == null) {
      _createNewGroup(position);
    } else {
      _addToExistingGroup(position, bestGroup);
    }
  }

  /// Computes position→group confidence and selection decision.
  _ConfidenceResult _calculateConfidence(
    RecognizedPosition position,
    RecognizedGroup group,
    int currentBestConfidence,
  ) {
    final productConfidence = group.calculateProductConfidence(
      position.product,
    );
    final priceConfidence = group.calculatePriceConfidence(position.price);

    final positionConfidence = position.copyWith(
      product: position.product.copyWith(confidence: productConfidence),
      price: position.price.copyWith(confidence: priceConfidence),
    );

    final sameTimestamp = group.members.any(
      (p) => position.timestamp == p.timestamp,
    );

    final repText = _groupRepresentativeText(group);
    final incText = position.product.normalizedText;
    final fuzzy = ReceiptOcrText.similarity(repText, incText);
    final repTok = ReceiptOcrText.tokens(repText);
    final incTok = ReceiptOcrText.tokens(incText);
    final sameBrand =
        ReceiptOcrText.brand(repText) == ReceiptOcrText.brand(incText);
    final variantDifferent =
        sameBrand &&
        repTok.isNotEmpty &&
        incTok.isNotEmpty &&
        !const SetEquality().equals(repTok, incTok);
    final baseMin = _opts.tuning.optimizerMinProductSimToMerge;
    final minNeeded =
        variantDifferent ? _opts.tuning.optimizerVariantMinSim : baseMin;

    final looksDissimilar = fuzzy < minNeeded;
    final thr = _opts.tuning.optimizerConfidenceThreshold;
    final shouldUseGroup =
        !sameTimestamp &&
        !looksDissimilar &&
        positionConfidence.confidence >= thr &&
        positionConfidence.confidence > currentBestConfidence;

    ReceiptLogger.log('conf', {
      'pos': ReceiptLogger.posKey(position),
      'grp': ReceiptLogger.grpKey(group),
      'price': position.price.value,
      'prodC': productConfidence.value,
      'priceC': priceConfidence.value,
      'thr': thr,
      'fuzzy': fuzzy,
      'use': shouldUseGroup,
      'why':
          sameTimestamp
              ? 'same-ts'
              : looksDissimilar
              ? 'lex-low'
              : positionConfidence.confidence < thr
              ? 'conf-low'
              : positionConfidence.confidence <= currentBestConfidence
              ? 'not-best'
              : 'ok',
    });

    return _ConfidenceResult(
      productConfidence: positionConfidence.product.confidence!,
      priceConfidence: positionConfidence.price.confidence!,
      confidence: positionConfidence.confidence,
      shouldUseGroup: shouldUseGroup,
    );
  }

  /// Creates a fresh group for the given position.
  void _createNewGroup(RecognizedPosition position) {
    final maxCacheSize = _opts.tuning.optimizerMaxCacheSize;
    final newGroup = RecognizedGroup(maxGroupSize: maxCacheSize);
    position.group = newGroup;
    position.operation = Operation.added;
    newGroup.addMember(position);
    _groups.add(newGroup);
    ReceiptLogger.log('group.new', {
      'grp': ReceiptLogger.grpKey(newGroup),
      'pos': ReceiptLogger.posKey(position),
    });
  }

  /// Adds a position to an existing group.
  void _addToExistingGroup(RecognizedPosition position, RecognizedGroup group) {
    position.group = group;
    position.operation = Operation.updated;
    group.addMember(position);
    ReceiptLogger.log('group.add', {
      'grp': ReceiptLogger.grpKey(group),
      'pos': ReceiptLogger.posKey(position),
      'm': group.members.length,
    });
  }

  /// Builds a merged, ordered receipt from stable groups and updates entities.
  RecognizedReceipt _createOptimizedReceipt(
    RecognizedReceipt receipt, {
    bool test = false,
  }) {
    if (!test && receipt.isValid && receipt.isConfirmed) return receipt;

    ReceiptLogger.log('opt.in', {
      'n': receipt.positions.length,
      'calc': receipt.calculatedTotal.value.toStringAsFixed(2),
      'total?': receipt.total?.value,
    });

    final stabilityThreshold = _opts.tuning.optimizerStabilityThreshold;
    final quarter = ReceiptRuntime.tuning.optimizerMaxCacheSize ~/ 4;
    final stableGroups =
        _groups
            .where(
              (g) =>
                  (g.stability >= stabilityThreshold &&
                      g.members.length >= quarter) ||
                  test,
            )
            .toList();

    _learnOrder(receipt);
    stableGroups.sort(_compareGroupsForOrder);

    final mergedReceipt = RecognizedReceipt.empty();

    for (final group in stableGroups) {
      final best = maxBy(group.members, (p) => p.confidence);
      final latest = maxBy(group.members, (p) => p.timestamp);
      if (best == null || latest == null) continue;

      final patched = best.copyWith(
        product: best.product.copyWith(line: latest.product.line),
        price: best.price.copyWith(line: latest.price.line),
      )..operation = latest.operation;

      ReceiptLogger.log('merge.keep', {
        'grp': ReceiptLogger.grpKey(group),
        'pos': ReceiptLogger.posKey(patched),
        'bestC': best.confidence,
        'latestTs': latest.timestamp.millisecondsSinceEpoch,
      });

      mergedReceipt.positions.add(patched);
    }

    mergedReceipt.store = receipt.store;
    mergedReceipt.total = receipt.total;
    mergedReceipt.totalLabel = receipt.totalLabel;
    mergedReceipt.purchaseDate = receipt.purchaseDate;
    mergedReceipt.bounds = receipt.bounds;

    _updateEntities(mergedReceipt);

    ReceiptLogger.log('opt.out', {
      'n': mergedReceipt.positions.length,
      'calc': mergedReceipt.calculatedTotal.value.toStringAsFixed(2),
      'total?': mergedReceipt.total?.value,
    });

    return mergedReceipt;
  }

  /// Refreshes the `entities` list from receipt fields and positions.
  void _updateEntities(RecognizedReceipt receipt) {
    receipt.entities?.clear();

    final store = receipt.store;
    if (store != null) {
      receipt.entities?.add(
        RecognizedStore(value: store.value, line: store.line),
      );
    }

    final products = receipt.positions.map((p) => p.product);
    receipt.entities?.addAll(
      products.map((p) => RecognizedProduct(value: p.value, line: p.line)),
    );

    final prices = receipt.positions.map((p) => p.price);
    receipt.entities?.addAll(
      prices.map((pr) => RecognizedPrice(value: pr.value, line: pr.line)),
    );

    final total = receipt.total;
    if (total != null) {
      receipt.entities?.add(
        RecognizedTotal(value: total.value, line: total.line),
      );
    }

    final totalLabel = receipt.totalLabel;
    if (totalLabel != null) {
      receipt.entities?.add(
        RecognizedTotalLabel(value: totalLabel.value, line: totalLabel.line),
      );
    }

    final purchaseDate = receipt.purchaseDate;
    if (purchaseDate != null) {
      receipt.entities?.add(
        RecognizedPurchaseDate(
          value: purchaseDate.value,
          line: purchaseDate.line,
        ),
      );
    }

    final bounds = receipt.bounds;
    if (bounds != null) {
      receipt.entities?.add(
        RecognizedBounds(value: bounds.value, line: bounds.line),
      );
    }
  }

  void _reconcileToTotal(RecognizedReceipt receipt) {
    final total = receipt.total?.value;
    if (total == null) return;
    if (receipt.positions.isEmpty) return;

    final tol = _opts.tuning.optimizerTotalTolerance;
    final targetC = _toCents(total);
    final beforeC = _sumCents(receipt.positions);

    final beforeLen = receipt.positions.length;
    receipt.positions.removeWhere(
      (pos) => (pos.price.value - total).abs() <= tol,
    );
    final removedAsTotal = beforeLen - receipt.positions.length;

    if (removedAsTotal > 0) {
      ReceiptLogger.log('recon.drop_total_like', {'removed': removedAsTotal});
    }

    int currentC = _sumCents(receipt.positions);
    final deltaC = currentC - targetC;
    if (deltaC.abs() <= (tol * 100).round()) {
      ReceiptLogger.log('recon.within_tol', {
        'sum': currentC / 100.0,
        'target': targetC / 100.0,
        'tol': tol,
      });
      return;
    }

    final int maxCandidates = beforeLen ~/ 2;
    final candidates = List<RecognizedPosition>.from(receipt.positions)..sort(
      (a, b) => (a.group?.members.length ?? 0).compareTo(
        b.group?.members.length ?? 0,
      ),
    );
    final pool = candidates.take(maxCandidates).toList();

    if (pool.length <= 1) return;

    final targetRemove = deltaC.abs();
    final toRemoveIdx = _pickSubsetToDrop(pool, targetRemove, beamWidth: 256);

    if (toRemoveIdx.isEmpty) {
      final beforeErr = (currentC - targetC).abs();
      for (final p in pool) {
        final after =
            currentC - _toCents(p.price.value) * (deltaC > 0 ? 1 : -1);
        final afterErr = (after - targetC).abs();
        if (afterErr < beforeErr) {
          receipt.positions.remove(p);
          p.group?.members.remove(p);
          ReceiptLogger.log('recon.greedy_drop', {
            'price': p.price.value,
            'conf': p.confidence,
            'err_before': beforeErr / 100.0,
            'err_after': afterErr / 100.0,
          });
          currentC = after;
          break;
        }
      }
    } else {
      final toRemove = toRemoveIdx.map((i) => pool[i]).toSet();
      int removedCount = 0;
      int removedCents = 0;
      for (final p in toRemove) {
        removedCount += receipt.positions.remove(p) ? 1 : 0;
        p.group?.members.remove(p);
        removedCents += _toCents(p.price.value);
      }
      ReceiptLogger.log('recon.subset_drop', {
        'removed': removedCount,
        'removed_sum': removedCents / 100.0,
        'sum_before': beforeC / 100.0,
        'sum_after': _sumCents(receipt.positions) / 100.0,
        'target': targetC / 100.0,
      });
    }

    final emptied = _groups.where((g) => g.members.isEmpty).toList();
    if (emptied.isNotEmpty) _purgeGroups(emptied.toSet());
  }

  /// Picks a subset (indexes into [pool]) to drop so that the sum of their prices
  /// (in cents) best approximates [targetRemoveC]. Beam search capped by [beamWidth].
  Set<int> _pickSubsetToDrop(
    List<RecognizedPosition> pool,
    int targetRemoveC, {
    int beamWidth = 256,
  }) {
    if (targetRemoveC <= 0) return const <int>{};

    final cents = pool.map((p) => _toCents(p.price.value)).toList();

    List<_State> beam = <_State>[_State(0, 0, 101)];
    for (int i = 0; i < cents.length; i++) {
      final price = cents[i];
      final conf = pool[i].confidence;

      final next = <_State>[];
      for (final s in beam) {
        next.add(s);

        final ns = s.sum + price;
        final nm = s.mask | (1 << i);
        final nw = math.min(s.worstC, conf);
        next.add(_State(ns, nm, nw));
      }

      next.sort((a, b) {
        final da = (targetRemoveC - a.sum).abs();
        final db = (targetRemoveC - b.sum).abs();
        if (da != db) return da.compareTo(db);

        final ca = _bitCount(a.mask);
        final cb = _bitCount(b.mask);
        if (ca != cb) return ca.compareTo(cb);

        return a.worstC.compareTo(b.worstC);
      });
      if (next.length > beamWidth) next.removeRange(beamWidth, next.length);
      beam = next;
    }

    final best = beam.first;
    return _maskToSet(best.mask);
  }

  /// Counts bits in an int.
  int _bitCount(int x) {
    int c = 0;
    int v = x;
    while (v != 0) {
      v &= (v - 1);
      c++;
    }
    return c;
  }

  /// Converts a bitmask of indexes to a Set.
  Set<int> _maskToSet(int mask) {
    final out = <int>{};
    int m = mask;
    int i = 0;
    while (m != 0) {
      if ((m & 1) == 1) out.add(i);
      m >>= 1;
      i++;
    }
    return out;
  }

  /// Sum of position prices in cents.
  int _sumCents(List<RecognizedPosition> ps) =>
      ps.fold<int>(0, (a, p) => a + _toCents(p.price.value));

  /// Convert a price to cents safely.
  int _toCents(num v) => (v * 100).round();

  /// Learns vertical ordering of groups using observed Y coordinates (EWMA + pairwise counts).
  void _learnOrder(RecognizedReceipt receipt) {
    final observed = <_Obs>[];
    for (final p in receipt.positions) {
      final g = p.group;
      if (g == null) continue;
      final y = p.product.line.boundingBox.center.dy;
      observed.add(_Obs(group: g, y: y, ts: p.timestamp));
    }
    if (observed.isEmpty) return;

    observed.sort((a, b) => a.y.compareTo(b.y));

    final now = DateTime.now();
    final alpha = _opts.tuning.optimizerEwmaAlpha;
    for (final o in observed) {
      final s = _orderStats.putIfAbsent(
        o.group,
        () => _OrderStats(firstSeen: now),
      );
      s.orderY = s.hasY ? (1 - alpha) * s.orderY + alpha * o.y : o.y;
      s.hasY = true;
      if (s.firstSeen.isAfter(o.ts)) s.firstSeen = o.ts;
    }

    for (int i = 0; i < observed.length; i++) {
      for (int j = i + 1; j < observed.length; j++) {
        final a = observed[i].group;
        final b = observed[j].group;
        final sa = _orderStats[a]!;
        sa.aboveCounts[b] = (sa.aboveCounts[b] ?? 0) + 1;
      }
    }

    final decayThreshold = _opts.tuning.optimizerAboveCountDecayThreshold;
    for (final s in _orderStats.values) {
      final total = s.aboveCounts.values.fold<int>(0, (a, b) => a + b);
      if (total > decayThreshold) {
        s.aboveCounts.updateAll((_, v) => math.max(1, v ~/ 2));
      }
    }

    ReceiptLogger.log('order.learn', {
      'stats':
          _orderStats.entries
              .map(
                (e) => {
                  'g': ReceiptLogger.grpKey(e.key),
                  'y': e.value.orderY,
                  'hasY': e.value.hasY,
                  'seen': e.value.firstSeen.millisecondsSinceEpoch,
                },
              )
              .toList(),
    });
  }

  /// Comparator for group ordering with tie-breakers and history.
  int _compareGroupsForOrder(RecognizedGroup a, RecognizedGroup b) {
    final tiePx = _opts.tuning.optimizerTotalTolerance.toDouble();

    final sa = _orderStats[a];
    final sb = _orderStats[b];

    if (sa != null && sb != null && sa.hasY && sb.hasY) {
      final dy = (sa.orderY - sb.orderY).abs();
      if (dy > tiePx) return sa.orderY.compareTo(sb.orderY);

      final ab = sa.aboveCounts[b] ?? 0;
      final ba = sb.aboveCounts[a] ?? 0;
      if (ab != ba) return (ab > ba) ? -1 : 1;

      final t = sa.firstSeen.compareTo(sb.firstSeen);
      if (t != 0) return t;
    }

    final ay = _medianProjectedY(a);
    final by = _medianProjectedY(b);
    if (ay != by) return ay.compareTo(by);

    final at = _earliestTimestamp(a.members);
    final bt = _earliestTimestamp(b.members);
    return at.compareTo(bt);
  }

  /// Detects very early weak outliers.
  bool _isEarlyOutlier(RecognizedGroup g, DateTime now) {
    final grace = Duration(milliseconds: 500);

    final staleForAWhile = now.difference(g.timestamp) >= grace;
    final veryWeak =
        g.stability < (_opts.tuning.optimizerStabilityThreshold ~/ 2) &&
        g.confidence < (_opts.tuning.optimizerConfidenceThreshold ~/ 2);
    final tiny = g.members.length <= 1;
    return staleForAWhile && veryWeak && tiny;
  }

  /// Returns a representative product text for a group.
  String _groupRepresentativeText(RecognizedGroup g) {
    final best = maxBy(g.members, (p) => p.stability);
    return (best?.product.normalizedText ??
        g.members.first.product.normalizedText);
  }

  /// Removes [toRemove] from `_groups` and cleans dependent structures.
  void _purgeGroups(Set<RecognizedGroup> toRemove) {
    _groups.removeWhere(toRemove.contains);
    for (final g in toRemove) {
      _orderStats.remove(g);
    }
    for (final s in _orderStats.values) {
      for (final g in toRemove) {
        s.aboveCounts.remove(g);
      }
    }
  }

  /// Median Y for all members of [g].
  double _medianProjectedY(RecognizedGroup g) {
    if (g.members.isEmpty) return double.infinity;
    final ys =
        g.members.map((p) => p.product.line.boundingBox.center.dy).toList()
          ..sort();
    return ys[ys.length ~/ 2];
  }

  /// Earliest timestamp in [ps], or epoch for empty lists.
  DateTime _earliestTimestamp(List<RecognizedPosition> ps) =>
      ps.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : ps.map((p) => p.timestamp).reduce((x, y) => x.isBefore(y) ? x : y);
}

final class _State {
  final int sum;
  final int mask;
  final int worstC;

  _State(this.sum, this.mask, this.worstC);
}

/// Result of evaluating how well a position fits a group.
final class _ConfidenceResult {
  /// Product-side confidence computed by the group.
  final Confidence productConfidence;

  /// Price-side confidence computed by the group.
  final Confidence priceConfidence;

  /// Combined confidence used for the selection decision (0–100).
  final int confidence;

  /// Whether the position should be assigned to the group.
  final bool shouldUseGroup;

  /// Creates a confidence result.
  const _ConfidenceResult({
    required this.productConfidence,
    required this.priceConfidence,
    required this.confidence,
    required this.shouldUseGroup,
  });

  @override
  String toString() =>
      '_ConfidenceResult(prod:${productConfidence.value}, '
      'price:${priceConfidence.value}, conf:$confidence, use:$shouldUseGroup)';
}

/// Observation of a group's vertical position at a given time.
final class _Obs {
  /// The group being observed.
  final RecognizedGroup group;

  /// Projected Y coordinate (skew-aware).
  final double y;

  /// Timestamp of the observation.
  final DateTime ts;

  /// Creates an observation.
  _Obs({required this.group, required this.y, required this.ts});
}

/// Running ordering statistics for a group (EWMA + pairwise counts).
final class _OrderStats {
  /// Exponentially weighted moving average of the group's Y.
  double orderY = 0;

  /// Whether [orderY] has been initialized.
  bool hasY = false;

  /// First time the group was seen.
  DateTime firstSeen;

  /// Count of times this group was observed above another group.
  final Map<RecognizedGroup, int> aboveCounts = {};

  /// Creates ordering stats.
  _OrderStats({required this.firstSeen});
}
