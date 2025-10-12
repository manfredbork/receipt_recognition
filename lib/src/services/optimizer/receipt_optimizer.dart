import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/optimizer/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';
import 'package:receipt_recognition/src/utils/geometry/index.dart';
import 'package:receipt_recognition/src/utils/logging/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

part 'receipt_confidence.dart';
part 'receipt_group_maintenance.dart';
part 'receipt_ordering.dart';
part 'receipt_sum_selection.dart';

/// Interface for receipt optimization components.
abstract class Optimizer {
  /// Initializes or resets the optimizer state.
  void init();

  /// Processes a receipt and returns an optimized version.
  ///
  /// Set [test] to true to always return a merged/optimized receipt.
  RecognizedReceipt optimize(
    RecognizedReceipt receipt, {
    ReceiptOptions? options,
    bool test = false,
  });

  /// Releases resources used by the optimizer.
  void close();
}

/// Default implementation of receipt optimizer that uses confidence scoring and grouping.
final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedGroup> _groups = [];
  final List<RecognizedStore> _stores = [];
  final List<RecognizedSum> _sums = [];
  final List<_SumCandidate> _sumCandidates = [];
  final Map<RecognizedGroup, _OrderStats> _orderStats = {};

  final ReceiptThresholder _thresholder;
  final int _loopThreshold;
  final int _sumConfirmationThreshold;
  final int _stabilityThreshold;
  final int _confidenceThreshold;
  final int _maxCacheSize;
  final int _maxGroups;
  final Duration _invalidateInterval;
  final double _ewmaAlpha;

  int _unchangedCount = 0;
  bool _shouldInitialize = false;
  bool _needsRegrouping = false;
  String? _lastFingerprint;
  double? _lastAngleRad;
  double? _lastAngleDeg;
  RecognizedPurchaseDate? _purchaseDate;

  /// Creates a new receipt optimizer with configurable thresholds.
  ReceiptOptimizer({
    int? loopThreshold,
    int? sumConfirmationThreshold,
    int? confidenceThreshold,
    int? stabilityThreshold,
    bool? highPrecision,
    Duration? invalidateInterval,
  }) : _confidenceThreshold =
           confidenceThreshold ?? ReceiptConstants.optimizerConfidenceThreshold,
       _thresholder = ReceiptThresholder(
         baseThreshold:
             confidenceThreshold ??
             ReceiptConstants.optimizerConfidenceThreshold,
       ),
       _loopThreshold =
           loopThreshold ?? ReceiptConstants.optimizerLoopThreshold,
       _sumConfirmationThreshold =
           sumConfirmationThreshold ??
           ReceiptConstants.optimizerSumConfirmationThreshold,
       _stabilityThreshold =
           stabilityThreshold ?? ReceiptConstants.optimizerStabilityThreshold,
       _invalidateInterval =
           invalidateInterval ??
           Duration(
             milliseconds: ReceiptConstants.optimizerInvalidateIntervalMs,
           ),
       _ewmaAlpha = ReceiptConstants.optimizerEwmaAlpha,
       _maxCacheSize =
           highPrecision == true
               ? ReceiptConstants.optimizerPrecisionHigh
               : ReceiptConstants.optimizerPrecisionNormal,
       _maxGroups = ReceiptConstants.optimizerMaxGroups;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() => _shouldInitialize = true;

  /// Processes a receipt and returns an optimized version.
  @override
  RecognizedReceipt optimize(
    RecognizedReceipt receipt, {
    ReceiptOptions? options,
    bool test = false,
  }) {
    _initializeIfNeeded();
    _checkConvergence(receipt);
    _updateStores(receipt);
    _updateSums(receipt);
    _updatePurchaseDate(receipt);
    _optimizeStore(receipt);
    _optimizeSum(receipt);
    _optimizePurchaseDate(receipt);
    _cleanupGroups();
    _resetOperations();
    _processPositions(receipt);
    _updateEntities(receipt);
    return _createOptimizedReceipt(receipt, options: options, test: test);
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
    _sumCandidates.clear();
    _orderStats.clear();
    _lastAngleRad = null;
    _lastAngleDeg = null;
    _shouldInitialize = false;
    _needsRegrouping = false;
    _unchangedCount = 0;
    _lastFingerprint = null;
    _purchaseDate = null;
  }

  /// Tracks convergence to avoid infinite loops and trigger regrouping.
  void _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.normalizedText}:${p.price.value}')
        .join(',');
    final sumHash = receipt.sum?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$sumHash';

    if (_lastFingerprint == fingerprint) {
      _unchangedCount++;
      if (_unchangedCount == (_loopThreshold ~/ 2)) _needsRegrouping = true;
      if (_unchangedCount >= _loopThreshold) return;
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
    if (_stores.length > _maxCacheSize) _stores.removeAt(0);
  }

  /// Updates sum history and confirms stable sum candidates.
  void _updateSums(RecognizedReceipt receipt) {
    final sum = receipt.sum;
    if (sum == null) return;

    _sums.add(sum);

    final angleDeg =
        receipt.boundingBox?.skewAngle ??
        ReceiptSkewEstimator.estimateDegrees(receipt);
    final rot = ReceiptRotator(angleDeg);
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();

    final sumLabel = receipt.entities
        ?.whereType<RecognizedSumLabel>()
        .firstWhereOrNull((label) {
          final dy = (rot.yCenter(label.line) - rot.yCenter(sum.line)).abs();
          final isRightOfLabel =
              rot.xCenter(sum.line) >= rot.maxXOf(label.line.boundingBox) - tol;
          return dy <= tol && isRightOfLabel;
        });

    if (sumLabel == null) return;

    final vd =
        (rot.yCenter(sumLabel.line) - rot.yCenter(sum.line)).abs().round();
    final candidate = _SumCandidate(
      label: sumLabel,
      sum: sum,
      verticalDistance: vd,
    );
    final existing =
        _sumCandidates.where((c) => c.matches(candidate)).firstOrNull;
    existing != null ? existing.confirm() : _sumCandidates.add(candidate);
    if (_sumCandidates.length > _maxCacheSize) _sumCandidates.removeAt(0);
  }

  /// Updates purchase date cache.
  void _updatePurchaseDate(RecognizedReceipt receipt) {
    final pd = receipt.purchaseDate;
    if (pd != null) _purchaseDate ??= pd;
  }

  /// Fills missing store from frequency in history.
  void _optimizeStore(RecognizedReceipt receipt) {
    if (receipt.store != null || _stores.isEmpty) return;
    final lastStore = _stores.lastOrNull;
    final mostFrequent =
        ReceiptNormalizer.sortByFrequency(
          _stores.map((c) => c.value).toList(),
        ).lastOrNull;
    if (lastStore != null) {
      receipt.store = lastStore.copyWith(value: mostFrequent);
    }
  }

  /// Fills missing purchase date from cache.
  void _optimizePurchaseDate(RecognizedReceipt receipt) =>
      receipt.purchaseDate ??= _purchaseDate;

  /// Fills or overwrites the receipt sum from history.
  void _optimizeSum(RecognizedReceipt receipt) {
    final stable = _pickStableSum(receipt);
    final hasConfirmed = stable != null;

    if (_sums.isEmpty) {
      ReceiptLogger.log('sum.opt', {
        'status': 'no-sums-in-cache',
        'receiptSum?': receipt.sum?.value,
      });
      return;
    }

    final freqSorted = ReceiptNormalizer.sortByFrequency(
      _sums.map((s) => s.formattedValue).toList(),
    );
    final mostFrequentValue = freqSorted.isNotEmpty ? freqSorted.last : null;
    final parsed =
        mostFrequentValue != null
            ? ReceiptFormatter.parse(mostFrequentValue)
            : null;
    final template = _sums.last;

    if (hasConfirmed || receipt.sum == null) {
      if (parsed != null) receipt.sum = template.copyWith(value: parsed);
      if (hasConfirmed && receipt.sumLabel == null) {
        receipt.sumLabel = stable.label;
      }
    }

    if (hasConfirmed) _demoteOtherConfirmedSums(stable);

    ReceiptLogger.log('sum.opt', {
      'hasConfirmed': hasConfirmed,
      'stable?':
          hasConfirmed
              ? {
                'label': stable.label.value,
                'sum': stable.sum.value,
                'conf': stable.confirmations,
                'vd': stable.verticalDistance,
              }
              : null,
      'mostFreq': mostFrequentValue,
      'parsed': parsed,
      'receiptSumAfter': receipt.sum?.value,
      'sumsCached': _sums.length,
      'candidates': _sumCandidates.length,
      'action':
          hasConfirmed
              ? 'overwrite-with-most-frequent+demote-others'
              : (receipt.sum == null
                  ? 'backfill-most-frequent'
                  : 'keep-existing'),
    });
  }

  /// Demotes all other confirmed sum candidates so only [keep] remains confirmed.
  void _demoteOtherConfirmedSums(_SumCandidate keep) {
    for (final c in _sumCandidates) {
      if (!identical(c, keep) && c.confirmations >= _sumConfirmationThreshold) {
        final old = c.confirmations;
        c.confirmations = 1;
        ReceiptLogger.log('sum.demote', {
          'label': c.label.value,
          'sum': c.sum.value,
          'oldConf': old,
          'newConf': c.confirmations,
          'keptLabel': keep.label.value,
          'keptSum': keep.sum.value,
        });
      }
    }
  }

  /// Removes empty/outlier/stale groups and trims to cap.
  void _cleanupGroups() {
    final now = DateTime.now();
    final cap = _maxGroups;

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

    final overCap = _groups.length > cap;

    var sumOverinflated = false;
    final calc = _groups.fold<double>(0.0, (a, g) => a + _groupBestPrice(g));
    final detectedSum = _sums.isNotEmpty ? _sums.last.value : 0.0;
    if (detectedSum > 0 &&
        calc > detectedSum * (1 + ReceiptConstants.heuristicQuarter)) {
      sumOverinflated = true;
      ReceiptLogger.log('group.overinflated', {
        'calc': calc,
        'detected': detectedSum,
        'ratio': calc / detectedSum,
      });
    }

    final doomed =
        _groups
            .where((g) => _shouldKillGroup(g, now, overCap || sumOverinflated))
            .toList();
    if (doomed.isNotEmpty) _purgeGroups(doomed.toSet());

    if (_groups.length > cap) {
      _groups.sort(
        (a, b) => _evictScore(b, now).compareTo(_evictScore(a, now)),
      );
      while (_groups.length > cap) {
        final g = _groups.removeLast();
        ReceiptLogger.log('group.evict', {
          'grp': ReceiptLogger.grpKey(g),
          'stb': g.stability,
          'conf': g.confidence,
          'ageMs': now.difference(g.timestamp).inMilliseconds,
        });
        _orderStats.remove(g);
        for (final s in _orderStats.values) {
          s.aboveCounts.remove(g);
        }
      }
    }
  }

  /// Resets per-frame operation markers on positions.
  void _resetOperations() {
    for (final group in _groups) {
      for (final position in group.members) {
        position.operation = Operation.none;
      }
    }
  }

  /// Processes positions, optionally respecting a confirmed stable sum.
  void _processPositions(RecognizedReceipt receipt) {
    final stableSum = _pickStableSum(receipt);
    final isStableSumConfirmed = stableSum != null;

    ReceiptLogger.log('sum.candidates', {
      'cands':
          _sumCandidates
              .map(
                (c) => {
                  'txt': c.label.value,
                  'sum': c.sum.value,
                  'vd': c.verticalDistance,
                  'conf': c.confirmations,
                },
              )
              .toList(),
    });

    ReceiptLogger.log('sum.stable', {
      'has': isStableSumConfirmed,
      'picked': stableSum?.sum.value,
      'vd': stableSum?.verticalDistance,
    });

    for (final position in receipt.positions) {
      if (isStableSumConfirmed) {
        final matchesStableSum =
            (position.price.value - stableSum.sum.value).abs() <=
            ReceiptConstants.sumTolerance;
        if (matchesStableSum) continue;
      }
      _processPosition(position);
    }

    _thresholder.update(
      recognizedSum: receipt.sum?.value.toDouble(),
      calculatedSum: receipt.calculatedSum.value.toDouble(),
    );

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
    final effectiveThreshold = _thresholder.threshold;

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
    final baseMin = ReceiptConstants.optimizerMinProductSimToMerge;
    final minNeeded =
        variantDifferent ? ReceiptConstants.optimizerVariantMinSim : baseMin;
    final looksDissimilar = fuzzy < minNeeded;

    final shouldUseGroup =
        !sameTimestamp &&
        !looksDissimilar &&
        positionConfidence.confidence >= effectiveThreshold &&
        positionConfidence.confidence > currentBestConfidence;

    ReceiptLogger.log('conf', {
      'pos': ReceiptLogger.posKey(position),
      'grp': ReceiptLogger.grpKey(group),
      'price': position.price.value,
      'prodC': productConfidence.value,
      'priceC': priceConfidence.value,
      'effThr': effectiveThreshold,
      'fuzzy': fuzzy,
      'use': shouldUseGroup,
      'why':
          sameTimestamp
              ? 'same-ts'
              : looksDissimilar
              ? 'lex-low'
              : positionConfidence.confidence < effectiveThreshold
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
    final newGroup = RecognizedGroup(maxGroupSize: _maxCacheSize);
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
    ReceiptOptions? options,
    bool test = false,
  }) {
    if (!test && receipt.isValid) return receipt;

    ReceiptLogger.log('opt.in', {
      'n': receipt.positions.length,
      'calc': receipt.calculatedSum.value.toStringAsFixed(2),
      'sum?': receipt.sum?.value,
    });

    final stableGroups =
        _groups
            .where((g) => g.stability >= _stabilityThreshold || test)
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

    final stableSum = _pickStableSum(mergedReceipt);
    ReceiptLogger.log('out.gate', {
      'enabled': stableSum != null,
      'sum': stableSum?.sum.value,
      'vd': stableSum?.verticalDistance,
    });

    if (stableSum != null) {
      _removeOutliersToMatchSum(mergedReceipt, options: options);
    }

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
    final products = receipt.positions.map((p) => p.product);
    final prices = receipt.positions.map((p) => p.price);

    receipt.entities?.clear();
    final store = receipt.store;
    if (store != null) {
      receipt.entities?.add(
        RecognizedStore(value: store.value, line: store.line),
      );
    }
    receipt.entities?.addAll(
      products.map((p) => RecognizedProduct(value: p.value, line: p.line)),
    );
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

    final pd = receipt.purchaseDate;
    if (pd != null) {
      receipt.entities?.add(
        RecognizedPurchaseDate(value: pd.value, line: pd.line),
      );
    }

    final bb = receipt.boundingBox;
    if (bb != null) {
      receipt.entities?.add(
        RecognizedBoundingBox(value: bb.value, line: bb.line),
      );
    }
  }

  /// Applies the outlier-removal step to make sums consistent.
  void _removeOutliersToMatchSum(
    RecognizedReceipt receipt, {
    ReceiptOptions? options,
  }) =>
      ReceiptOutlierRemover.removeOutliersToMatchSum(receipt, options: options);

  /// Learns vertical ordering of groups using skew-aware projection.
  void _learnOrder(RecognizedReceipt receipt) {
    final angleDeg = ReceiptSkewEstimator.estimateDegrees(receipt);
    if (angleDeg.abs() < 0.5) {
      _lastAngleDeg = 0.0;
      _lastAngleRad = null;
    } else {
      _lastAngleDeg = angleDeg;
      _lastAngleRad = angleDeg * math.pi / 180.0;
    }

    final angleRad = _lastAngleRad;
    final observed = <_Obs>[];
    for (final p in receipt.positions) {
      final g = p.group;
      if (g == null) continue;
      final y = _projectedYFromLine(p.product.line, angleRad);
      observed.add(_Obs(group: g, y: y, ts: p.timestamp));
    }
    if (observed.isEmpty) return;

    observed.sort((a, b) => a.y.compareTo(b.y));

    final now = DateTime.now();
    for (final o in observed) {
      final s = _orderStats.putIfAbsent(
        o.group,
        () => _OrderStats(firstSeen: now),
      );
      s.orderY = s.hasY ? (1 - _ewmaAlpha) * s.orderY + _ewmaAlpha * o.y : o.y;
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

    for (final s in _orderStats.values) {
      final total = s.aboveCounts.values.fold<int>(0, (a, b) => a + b);
      if (total > ReceiptConstants.optimizerAboveCountDecayThreshold) {
        s.aboveCounts.updateAll((_, v) => math.max(1, v ~/ 2));
      }
    }

    ReceiptLogger.log('order.learn', {
      'angleDeg': _lastAngleDeg,
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
    final tiePx =
        (_lastAngleDeg?.abs() ?? 0) < 0.5
            ? (ReceiptConstants.boundingBoxBuffer ~/ 2)
            : ReceiptConstants.boundingBoxBuffer;

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
    final grace = _invalidateInterval ~/ 8;
    final staleForAWhile = now.difference(g.timestamp) >= grace;
    final veryWeak =
        g.stability < (_stabilityThreshold ~/ 2) &&
        g.confidence < (_confidenceThreshold ~/ 2);
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
}
