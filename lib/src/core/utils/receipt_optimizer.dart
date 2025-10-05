import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart' as fw;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Interface for receipt optimization components.
///
/// Optimizers improve recognition accuracy by processing and refining receipt data
/// over multiple scans.
abstract class Optimizer {
  /// Initializes or resets the optimizer state.
  void init();

  /// Processes a receipt and returns an optimized version.
  ///
  /// Set [test] to true to always return a merged/optimized receipt.
  RecognizedReceipt optimize(RecognizedReceipt receipt, {bool test = false});

  /// Releases resources used by the optimizer.
  void close();
}

/// Default implementation of receipt optimizer that uses confidence scoring and grouping.
///
/// Improves recognition accuracy by:
/// - Grouping similar items together
/// - Applying confidence thresholds
/// - Merging data from multiple scans
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
  int _unchangedCount;
  bool _shouldInitialize;
  bool _needsRegrouping;
  String? _lastFingerprint;
  double? _lastAngleRad;
  double? _lastAngleDeg;
  RecognizedPurchaseDate? _purchaseDate;

  /// Creates a new receipt optimizer with configurable thresholds.
  ///
  /// Defaults are sourced from [ReceiptConstants] so tuning is centralized.
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
       _maxGroups = ReceiptConstants.optimizerMaxGroups,
       _unchangedCount = 0,
       _shouldInitialize = false,
       _needsRegrouping = false;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() {
    _shouldInitialize = true;
  }

  /// Processes a receipt and returns an optimized version.
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt, {bool test = false}) {
    if (!_checkConvergence(receipt)) {
      return receipt;
    }

    _initializeIfNeeded();
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

    if (!test && receipt.isValid) {
      return receipt;
    } else {
      ReceiptLogger.log('opt.in', {
        'n': receipt.positions.length,
        'calc': receipt.calculatedSum.value.toStringAsFixed(2),
        'sum?': receipt.sum?.value,
      });

      final out = _createOptimizedReceipt(receipt, test: test);

      ReceiptLogger.log('opt.out', {
        'n': out.positions.length,
        'calc': out.calculatedSum.value.toStringAsFixed(2),
        'sum?': out.sum?.value,
      });
      return out;
    }
  }

  /// Clears caches and resets internal state if flagged.
  void _initializeIfNeeded() {
    if (_shouldInitialize) {
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
  }

  /// Tracks convergence to avoid infinite loops and trigger regrouping.
  bool _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.normalizedText}:${p.price.value}')
        .join(',');
    final sumHash = receipt.sum?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$sumHash';

    if (_lastFingerprint == fingerprint) {
      _unchangedCount++;
      if (_unchangedCount == (_loopThreshold ~/ 2)) {
        _needsRegrouping = true;
      }
      if (_unchangedCount >= _loopThreshold) {
        return false;
      }
    } else {
      _unchangedCount = 0;
    }

    _lastFingerprint = fingerprint;
    return true;
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
    if (receipt.store != null) {
      _stores.add(receipt.store!);
    }
    if (_stores.length > _maxCacheSize) {
      _stores.removeAt(0);
    }
  }

  /// Updates sum history and confirms stable sum candidates.
  void _updateSums(RecognizedReceipt receipt) {
    if (receipt.sum == null) return;

    _sums.add(receipt.sum!);

    final angleDeg =
        receipt.boundingBox?.skewAngle ??
        ReceiptSkewEstimator.estimateDegrees(receipt);
    final rot = ReceiptRotator(angleDeg);
    final tol = ReceiptConstants.boundingBoxBuffer.toDouble();

    final sumLabel = receipt.entities
        ?.whereType<RecognizedSumLabel>()
        .firstWhereOrNull((label) {
          final dy =
              (rot.yCenter(label.line) - rot.yCenter(receipt.sum!.line)).abs();
          final isRightOfLabel =
              rot.xCenter(receipt.sum!.line) >=
              rot.maxXOf(label.line.boundingBox) - tol;
          return dy <= tol && isRightOfLabel;
        });

    if (sumLabel != null) {
      final vd =
          (rot.yCenter(sumLabel.line) - rot.yCenter(receipt.sum!.line))
              .abs()
              .round();

      final candidate = _SumCandidate(
        label: sumLabel,
        sum: receipt.sum!,
        verticalDistance: vd,
      );

      final existing =
          _sumCandidates.where((c) => c.matches(candidate)).firstOrNull;
      if (existing != null) {
        existing.confirm();
      } else {
        _sumCandidates.add(candidate);
      }

      if (_sumCandidates.length > _maxCacheSize) {
        _sumCandidates.removeAt(0);
      }
    }
  }

  /// Updates purchase date cache.
  void _updatePurchaseDate(RecognizedReceipt receipt) {
    if (receipt.purchaseDate != null) {
      _purchaseDate ??= receipt.purchaseDate;
    }
  }

  /// Fills missing store from frequency in history.
  void _optimizeStore(RecognizedReceipt receipt) {
    if (receipt.store == null && _stores.isNotEmpty) {
      final lastStore = _stores.lastOrNull;
      if (lastStore != null) {
        final mostFrequent =
            ReceiptNormalizer.sortByFrequency(
              _stores.map((c) => c.value).toList(),
            ).lastOrNull;
        receipt.store = lastStore.copyWith(value: mostFrequent);
      }
    }
  }

  /// Fills missing purchase date from cache.
  void _optimizePurchaseDate(RecognizedReceipt receipt) {
    receipt.purchaseDate ??= _purchaseDate;
  }

  /// Fills or overwrites the receipt sum from history.
  ///
  /// - If a stable (confirmed) sum exists, always take the most frequent sum.
  /// - Otherwise, only backfill when the receipt sum is null.
  void _optimizeSum(RecognizedReceipt receipt) {
    final stable = minBy(
      _sumCandidates.where(
        (c) =>
            c.confirmations >= _sumConfirmationThreshold &&
            _isConfirmedSumValid(c, receipt),
      ),
      (c) => c.verticalDistance,
    );
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
      if (parsed != null) {
        receipt.sum = template.copyWith(value: parsed);
      }
      if (hasConfirmed && receipt.sumLabel == null) {
        receipt.sumLabel = stable.label;
      }
    }

    if (hasConfirmed) {
      _demoteOtherConfirmedSums(stable);
    }

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

  /// Removes empty / outlier / stale groups and trims to cap.
  void _cleanupGroups() {
    final now = DateTime.now();
    final cap = _maxGroups;
    final doomed = <RecognizedGroup>[];

    final emptied = _groups.where((g) => g.members.isEmpty).toList();
    for (final g in emptied) {
      ReceiptLogger.log('group.empty', {'grp': ReceiptLogger.grpKey(g)});
    }
    if (emptied.isNotEmpty) {
      final emptiedSet = emptied.toSet();
      _groups.removeWhere(emptiedSet.contains);
      for (final g in emptiedSet) {
        _orderStats.remove(g);
      }
      for (final s in _orderStats.values) {
        for (final g in emptiedSet) {
          s.aboveCounts.remove(g);
        }
      }
    }

    bool isEarlyOutlier(RecognizedGroup g) {
      final grace = _invalidateInterval ~/ 8;
      final staleForAWhile = now.difference(g.timestamp) >= grace;

      final veryWeak =
          g.stability < (_stabilityThreshold * 0.5) &&
          g.confidence < (_confidenceThreshold * 0.5);

      final tiny = g.members.length <= 1;

      return staleForAWhile && veryWeak && tiny;
    }

    for (final g in _groups) {
      if (isEarlyOutlier(g)) {
        ReceiptLogger.log('group.outlier', {
          'grp': ReceiptLogger.grpKey(g),
          'stb': g.stability,
          'conf': g.confidence,
          'ageMs': now.difference(g.timestamp).inMilliseconds,
        });
        doomed.add(g);
      }
    }

    if (doomed.isNotEmpty) {
      final doomedSet = doomed.toSet();
      _groups.removeWhere(doomedSet.contains);
      for (final g in doomedSet) {
        _orderStats.remove(g);
      }
      for (final s in _orderStats.values) {
        for (final g in doomedSet) {
          s.aboveCounts.remove(g);
        }
      }
      doomed.clear();
    }

    final overCap = _groups.length > cap;

    bool sumOverinflated = false;

    double groupBestPrice(RecognizedGroup g) {
      final best = maxBy(g.members, (p) => p.confidence);
      return best?.price.value.toDouble() ?? 0.0;
    }

    try {
      final calc = _groups.fold<double>(0.0, (a, g) => a + groupBestPrice(g));
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
    } catch (_) {}

    bool shouldKill(RecognizedGroup g) {
      final age = now.difference(g.timestamp);
      final tooOld = age >= _invalidateInterval;
      final tooWeak =
          g.stability < _stabilityThreshold ||
          g.confidence < _confidenceThreshold;

      final trigger = overCap || sumOverinflated;
      return trigger ? (tooOld || tooWeak) : (tooOld && tooWeak);
    }

    for (final g in _groups) {
      if (shouldKill(g)) {
        ReceiptLogger.log('group.kill', {
          'grp': ReceiptLogger.grpKey(g),
          'stb': g.stability,
          'conf': g.confidence,
          'ageMs': now.difference(g.timestamp).inMilliseconds,
          'overCap': overCap,
          'inflated': sumOverinflated,
        });
        doomed.add(g);
      }
    }

    if (doomed.isNotEmpty) {
      final doomedSet = doomed.toSet();
      _groups.removeWhere(doomedSet.contains);
      for (final g in doomedSet) {
        _orderStats.remove(g);
      }
      for (final s in _orderStats.values) {
        for (final g in doomedSet) {
          s.aboveCounts.remove(g);
        }
      }
    }

    if (_groups.length > cap) {
      double evictScore(RecognizedGroup g) {
        final isOld =
            now.difference(g.timestamp) >= _invalidateInterval ? 1 : 0;
        final weakStab = g.stability < _stabilityThreshold ? 1 : 0;
        final weakConf = g.confidence < _confidenceThreshold ? 1 : 0;
        return isOld * 2 + weakStab + weakConf + (_groups.indexOf(g) * 1e-6);
      }

      _groups.sort((a, b) => evictScore(b).compareTo(evictScore(a)));
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

  /// Normalizes common OCR quirks and strips non-alnum.
  String _ocrNorm(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final uc in lower.codeUnits) {
      final c = String.fromCharCode(uc);
      switch (c) {
        case '0':
          buf.write('o');
          break;
        case '1':
          buf.write('l');
          break;
        case 'i':
          buf.write('l');
          break;
        case '5':
          buf.write('s');
          break;
        case '8':
          buf.write('b');
          break;
        default:
          if (RegExp(r'[a-z0-9]').hasMatch(c)) {
            buf.write(c);
          } else {
            buf.write(' ');
          }
      }
    }
    return buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Fuzzy OCR-friendly similarity in [0,1] via fuzzywuzzy.
  double _fuzzySim(String a, String b) {
    final x = _ocrNorm(a), y = _ocrNorm(b);
    if (x.isEmpty && y.isEmpty) return 1.0;
    if (x.isEmpty || y.isEmpty) return 0.0;
    final r1 = fw.tokenSetRatio(x, y);
    final r2 = fw.tokenSortRatio(x, y);
    final r3 = fw.partialRatio(x, y);
    final best = r1 > r2 ? (r1 > r3 ? r1 : r3) : (r2 > r3 ? r2 : r3);
    return best / 100.0;
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
    final stableSum = minBy(
      _sumCandidates.where(
        (c) =>
            c.confirmations >= _sumConfirmationThreshold &&
            _isConfirmedSumValid(c, receipt),
      ),
      (c) => c.verticalDistance,
    );

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
    Confidence productConfidence = group.calculateProductConfidence(
      position.product,
    );
    Confidence priceConfidence = group.calculatePriceConfidence(position.price);

    final positionConfidence = position.copyWith(
      product: position.product.copyWith(confidence: productConfidence),
      price: position.price.copyWith(confidence: priceConfidence),
    );

    final bool sameTimestamp = group.members.any(
      (p) => position.timestamp == p.timestamp,
    );

    int effectiveThreshold = _thresholder.threshold;

    final repText = _groupRepresentativeText(group);
    final incText = position.product.normalizedText;
    final fuzzy = _fuzzySim(repText, incText);

    Set<String> toks(String s) {
      final x = _ocrNorm(s);
      return x.split(' ').where((t) => t.length >= 2).toSet();
    }

    String brand(String s) {
      final x = _ocrNorm(s).split(' ').where((t) => t.isNotEmpty).toList();
      return x.isEmpty ? '' : x.first;
    }

    final repTok = toks(repText);
    final incTok = toks(incText);
    final sameBrand = brand(repText) == brand(incText);
    final variantDifferent =
        sameBrand && repTok.isNotEmpty && incTok.isNotEmpty && repTok != incTok;
    final baseMin = ReceiptConstants.optimizerMinProductSimToMerge;
    final minNeeded =
        variantDifferent ? ReceiptConstants.optimizerVariantMinSim : baseMin;

    final looksDissimilar = fuzzy < minNeeded;

    final shouldUseGroup =
        !sameTimestamp &&
        !looksDissimilar &&
        positionConfidence.confidence >= effectiveThreshold &&
        positionConfidence.confidence > currentBestConfidence;

    final reason =
        sameTimestamp
            ? 'same-ts'
            : looksDissimilar
            ? 'lex-low'
            : positionConfidence.confidence < effectiveThreshold
            ? 'conf-low'
            : positionConfidence.confidence <= currentBestConfidence
            ? 'not-best'
            : 'ok';

    ReceiptLogger.log('conf', {
      'pos': ReceiptLogger.posKey(position),
      'grp': ReceiptLogger.grpKey(group),
      'price': position.price.value,
      'prodC': productConfidence.value,
      'priceC': priceConfidence.value,
      'effThr': effectiveThreshold,
      'fuzzy':
          (() {
            try {
              final repText = _groupRepresentativeText(group);
              final incText = position.product.normalizedText;
              return _fuzzySim(repText, incText);
            } catch (_) {
              return null;
            }
          })(),
      'use': reason == 'ok',
      'why': reason,
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
    bool test = false,
  }) {
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

      if (best != null && latest != null) {
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
    }

    mergedReceipt.store ??= receipt.store;
    mergedReceipt.sum ??= receipt.sum;
    mergedReceipt.sumLabel ??= receipt.sumLabel;
    mergedReceipt.purchaseDate ??= receipt.purchaseDate;
    mergedReceipt.boundingBox ??= receipt.boundingBox;

    final stableSum = minBy(
      _sumCandidates.where(
        (c) =>
            c.confirmations >= _sumConfirmationThreshold &&
            _isConfirmedSumValid(c, mergedReceipt),
      ),
      (c) => c.verticalDistance,
    );

    ReceiptLogger.log('out.gate', {
      'enabled': stableSum != null,
      'sum': stableSum?.sum.value,
      'vd': stableSum?.verticalDistance,
    });

    if (stableSum != null) {
      _removeOutliersToMatchSum(mergedReceipt);
    }

    _updateEntities(mergedReceipt);

    return mergedReceipt;
  }

  /// Refreshes the `entities` list from receipt fields and positions.
  void _updateEntities(RecognizedReceipt receipt) {
    final products = receipt.positions.map((p) => p.product);
    final prices = receipt.positions.map((p) => p.price);

    receipt.entities?.clear();
    if (receipt.store != null) {
      receipt.entities?.add(
        RecognizedStore(value: receipt.store!.value, line: receipt.store!.line),
      );
    }
    receipt.entities?.addAll(
      products.map(
        (product) =>
            RecognizedProduct(value: product.value, line: product.line),
      ),
    );
    receipt.entities?.addAll(
      prices.map(
        (price) => RecognizedPrice(value: price.value, line: price.line),
      ),
    );
    if (receipt.sum != null) {
      receipt.entities?.add(
        RecognizedSum(value: receipt.sum!.value, line: receipt.sum!.line),
      );
    }
    if (receipt.sumLabel != null) {
      receipt.entities?.add(
        RecognizedSumLabel(
          value: receipt.sumLabel!.value,
          line: receipt.sumLabel!.line,
        ),
      );
    }
    if (receipt.purchaseDate != null) {
      receipt.entities?.add(
        RecognizedPurchaseDate(
          value: receipt.purchaseDate!.value,
          line: receipt.purchaseDate!.line,
        ),
      );
    }
    if (receipt.boundingBox != null) {
      receipt.entities?.add(
        RecognizedBoundingBox(
          value: receipt.boundingBox!.value,
          line: receipt.boundingBox!.line,
        ),
      );
    }
  }

  /// Applies the outlier-removal step to make sums consistent.
  void _removeOutliersToMatchSum(RecognizedReceipt receipt) {
    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);
  }

  /// Checks whether a confirmed sum candidate is plausible for the receipt.
  bool _isConfirmedSumValid(
    _SumCandidate candidate,
    RecognizedReceipt receipt,
  ) {
    if (receipt.positions.length < 2) return false;

    final calculated = receipt.calculatedSum.value;
    return (candidate.sum.value - calculated).abs() <=
        ReceiptConstants.sumTolerance;
  }

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
    final cosA = angleRad != null ? math.cos(-angleRad) : null;
    final sinA = angleRad != null ? math.sin(-angleRad) : null;

    double projectedY(TextLine line) {
      final center = line.boundingBox.center;
      if (angleRad == null) return center.dy.toDouble();
      return center.dx * sinA! + center.dy * cosA!;
    }

    final observed = <_Obs>[];
    for (final p in receipt.positions) {
      final g = p.group;
      if (g == null) continue;
      final y = projectedY(p.product.line);
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
      if (s.firstSeen.isAfter(o.ts)) {
        s.firstSeen = o.ts;
      }
    }

    for (int i = 0; i < observed.length; i++) {
      for (int j = i + 1; j < observed.length; j++) {
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
            ? (ReceiptConstants.boundingBoxBuffer * 0.8).round()
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

    final angleRad = _lastAngleRad;
    double medianProjectedY(RecognizedGroup g) {
      if (g.members.isEmpty) return double.infinity;
      final ys =
          g.members
              .map((p) => _projectedYFromLine(p.product.line, angleRad))
              .toList()
            ..sort();
      return ys[ys.length ~/ 2];
    }

    final ay = medianProjectedY(a);
    final by = medianProjectedY(b);
    if (ay != by) return ay.compareTo(by);

    DateTime earliest(List<RecognizedPosition> ps) =>
        ps.isEmpty
            ? DateTime.fromMillisecondsSinceEpoch(0)
            : ps
                .map((p) => p.timestamp)
                .reduce((x, y) => x.isBefore(y) ? x : y);

    final at = earliest(a.members);
    final bt = earliest(b.members);
    return at.compareTo(bt);
  }

  /// Projects a line’s center onto Y using an optional skew angle.
  double _projectedYFromLine(TextLine line, double? angleRad) {
    final c = line.boundingBox.center;
    if (angleRad == null) return c.dy.toDouble();
    final cosA = math.cos(-angleRad), sinA = math.sin(-angleRad);
    return c.dx * sinA + c.dy * cosA;
  }

  /// Releases all resources used by the optimizer.
  @override
  void close() {
    _groups.clear();
    _stores.clear();
    _sums.clear();
    _shouldInitialize = false;
  }

  String _groupRepresentativeText(RecognizedGroup g) {
    final best = maxBy(g.members, (p) => p.confidence);
    return (best?.product.normalizedText ??
        g.members.first.product.normalizedText);
  }
}

class _ConfidenceResult {
  final Confidence productConfidence;
  final Confidence priceConfidence;
  final int confidence;
  final bool shouldUseGroup;

  _ConfidenceResult({
    required this.productConfidence,
    required this.priceConfidence,
    required this.confidence,
    required this.shouldUseGroup,
  });
}

class _SumCandidate {
  final RecognizedSumLabel label;
  final RecognizedSum sum;
  final int verticalDistance;
  int confirmations = 1;

  _SumCandidate({
    required this.label,
    required this.sum,
    required this.verticalDistance,
  });

  bool matches(_SumCandidate other) =>
      label.line.text == other.label.line.text &&
      (sum.value - other.sum.value).abs() <= ReceiptConstants.sumTolerance;

  void confirm() => confirmations++;
}

class _Obs {
  final RecognizedGroup group;
  final double y;
  final DateTime ts;

  _Obs({required this.group, required this.y, required this.ts});
}

class _OrderStats {
  double orderY = 0;
  bool hasY = false;
  DateTime firstSeen;
  final Map<RecognizedGroup, int> aboveCounts = {};

  _OrderStats({required this.firstSeen});
}
