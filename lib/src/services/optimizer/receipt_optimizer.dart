import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:receipt_recognition/src/models/index.dart';
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

  /// Cache of sums from recent frames.
  final List<RecognizedSum> _sums = [];

  /// Cache of sum labels from recent frames.
  final List<RecognizedSumLabel> _sumLabels = [];

  /// Cache of purchase dates from recent frames.
  final List<RecognizedPurchaseDate> _purchaseDates = [];

  /// Ordering stats by group.
  final Map<RecognizedGroup, _OrderStats> _orderStats = {};

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
      _updateSums(receipt);
      _updateSumLabels(receipt);
      _updatePurchaseDates(receipt);
      _optimizeStore(receipt);
      _optimizeSum(receipt);
      _optimizeSumLabel(receipt);
      _optimizePurchaseDate(receipt);
      _cleanupGroups();
      _resetOperations();
      _processPositions(receipt);
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
    _sums.clear();
    _sumLabels.clear();
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
    final sumHash = receipt.sum?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$sumHash';

    final loopThreshold = ReceiptRuntime.tuning.optimizerLoopThreshold;

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

  /// Updates sums history cache for later normalization.
  void _updateSums(RecognizedReceipt receipt) {
    final sum = receipt.sum;
    if (sum != null) _sums.add(sum);
    _trimCache(_sums);
  }

  /// Updates sum labels history cache for later normalization.
  void _updateSumLabels(RecognizedReceipt receipt) {
    final sumLabel = receipt.sumLabel;
    if (sumLabel != null) _sumLabels.add(sumLabel);
    _trimCache(_sumLabels);
  }

  /// Updates purchase dates history cache for later normalization.
  void _updatePurchaseDates(RecognizedReceipt receipt) {
    final purchaseDate = receipt.purchaseDate;
    if (purchaseDate != null) _purchaseDates.add(purchaseDate);
    _trimCache(_purchaseDates);
  }

  /// Trims a cache list to the configured precision size.
  void _trimCache(List list) {
    final maxCacheSize = ReceiptRuntime.tuning.optimizerPrecisionNormal;
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
    receipt.store = _stores.lastWhere((s) => s.value == mostFrequentStore.last);
  }

  /// Fills sum label with the most frequent value in history.
  void _optimizeSumLabel(RecognizedReceipt receipt) {
    if (_sumLabels.isEmpty) return;
    final mostFrequentSumLabel = ReceiptNormalizer.sortByFrequency(
      _sumLabels.map((c) => c.value).toList(),
    );
    receipt.sumLabel = _sumLabels.lastWhere(
      (sl) => sl.value == mostFrequentSumLabel.last,
    );
  }

  /// Fills sum with the most frequent value in history.
  void _optimizeSum(RecognizedReceipt receipt) {
    if (_sums.isEmpty) return;
    final mostFrequentSum = ReceiptNormalizer.sortByFrequency(
      _sums.map((c) => c.value.toString()).toList(),
    );
    receipt.sum = _sums.lastWhere(
      (s) => s.value.toString() == mostFrequentSum.last,
    );
  }

  /// Fills purchase date with the most frequent value in history.
  void _optimizePurchaseDate(RecognizedReceipt receipt) {
    if (_purchaseDates.isEmpty) return;
    final mostFrequentPurchaseDate = ReceiptNormalizer.sortByFrequency(
      _purchaseDates.map((c) => c.value).toList(),
    );
    receipt.purchaseDate = _purchaseDates.lastWhere(
      (pd) => pd.value == mostFrequentPurchaseDate.last,
    );
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
    var bestConfidence = 0;
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
    final baseMin = ReceiptRuntime.tuning.optimizerMinProductSimToMerge;
    final minNeeded =
        variantDifferent
            ? ReceiptRuntime.tuning.optimizerVariantMinSim
            : baseMin;

    final looksDissimilar = fuzzy < minNeeded;
    final thr = ReceiptRuntime.tuning.optimizerConfidenceThreshold;
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
    final maxCacheSize = ReceiptRuntime.tuning.optimizerPrecisionNormal;
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
    if (!test && receipt.isValid) return receipt;

    ReceiptLogger.log('opt.in', {
      'n': receipt.positions.length,
      'calc': receipt.calculatedSum.value.toStringAsFixed(2),
      'sum?': receipt.sum?.value,
    });

    final stabilityThreshold =
        ReceiptRuntime.tuning.optimizerStabilityThreshold;
    final stableGroups =
        _groups
            .where((g) => g.stability >= stabilityThreshold || test)
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

    mergedReceipt.store ??= receipt.store;
    mergedReceipt.sum ??= receipt.sum;
    mergedReceipt.sumLabel ??= receipt.sumLabel;
    mergedReceipt.purchaseDate ??= receipt.purchaseDate;
    mergedReceipt.boundingBox ??= receipt.boundingBox;

    _updateEntities(mergedReceipt);

    ReceiptLogger.log('opt.out', {
      'n': mergedReceipt.positions.length,
      'calc': mergedReceipt.calculatedSum.value.toStringAsFixed(2),
      'sum?': mergedReceipt.sum?.value,
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

    final sum = receipt.sum;
    if (sum != null) {
      receipt.entities?.add(RecognizedSum(value: sum.value, line: sum.line));
    }

    final sumLabel = receipt.sumLabel;
    if (sumLabel != null) {
      receipt.entities?.add(
        RecognizedSumLabel(value: sumLabel.value, line: sumLabel.line),
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

    final boundingBox = receipt.boundingBox;
    if (boundingBox != null) {
      receipt.entities?.add(
        RecognizedBoundingBox(value: boundingBox.value, line: boundingBox.line),
      );
    }
  }

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
    final alpha = ReceiptRuntime.tuning.optimizerEwmaAlpha;
    for (final o in observed) {
      final s = _orderStats.putIfAbsent(
        o.group,
        () => _OrderStats(firstSeen: now),
      );
      s.orderY = s.hasY ? (1 - alpha) * s.orderY + alpha * o.y : o.y;
      s.hasY = true;
      if (s.firstSeen.isAfter(o.ts)) s.firstSeen = o.ts;
    }

    for (var i = 0; i < observed.length; i++) {
      for (var j = i + 1; j < observed.length; j++) {
        final a = observed[i].group;
        final b = observed[j].group;
        final sa = _orderStats[a]!;
        sa.aboveCounts[b] = (sa.aboveCounts[b] ?? 0) + 1;
      }
    }

    final decayThreshold =
        ReceiptRuntime.tuning.optimizerAboveCountDecayThreshold;
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
    final tiePx = ReceiptRuntime.tuning.boundingBoxBuffer.toDouble();

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
    final invalidateMs = ReceiptRuntime.tuning.optimizerInvalidateIntervalMs;
    final grace = Duration(milliseconds: invalidateMs) ~/ 8;

    final staleForAWhile = now.difference(g.timestamp) >= grace;
    final veryWeak =
        g.stability <
            (ReceiptRuntime.tuning.optimizerStabilityThreshold ~/ 2) &&
        g.confidence <
            (ReceiptRuntime.tuning.optimizerConfidenceThreshold ~/ 2);
    final tiny = g.members.length <= 1;
    return staleForAWhile && veryWeak && tiny;
  }

  /// Returns a representative product text for a group.
  String _groupRepresentativeText(RecognizedGroup g) {
    final best = maxBy(g.members, (p) => p.confidence);
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
