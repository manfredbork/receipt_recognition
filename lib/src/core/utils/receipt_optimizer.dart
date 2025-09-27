import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Interface for receipt optimization components.
///
/// Optimizers improve recognition accuracy by processing and refining receipt data
/// over multiple scans.
abstract class Optimizer {
  /// Initializes or resets the optimizer state.
  void init();

  /// Processes a receipt to improve its recognition quality.
  ///
  /// Returns an optimized version of the input receipt.
  RecognizedReceipt optimize(RecognizedReceipt receipt);

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
  final List<RecognizedCompany> _companies = [];
  final List<RecognizedSum> _sums = [];
  final List<_SumCandidate> _sumCandidates = [];
  final ReceiptThresholder _thresholder;
  final int _loopThreshold;
  final int _sumConfirmationThreshold;
  final int _maxCacheSize;
  final int _stabilityThreshold;
  final Duration _invalidateInterval;

  // Add to ReceiptOptimizer fields:
  final Map<RecognizedGroup, _OrderStats> _orderStats = {};

  // Tunables
  static const double _ewmaAlpha = 0.3; // how quickly orderY adapts

  bool _shouldInitialize;
  bool _needsRegrouping;
  int _unchangedCount;
  String? _lastFingerprint;
  double? _lastAngleRad;
  double? _lastAngleDeg;

  /// Creates a new receipt optimizer with configurable thresholds.
  ///
  /// Parameters:
  /// - [loopThreshold]: Number of identical consecutive results before optimization halts
  /// - [sumConfirmationThreshold]: Minimum number of matching detections to confirm a sum
  /// - [maxCacheSize]: Maximum number of items to keep in memory
  /// - [confidenceThreshold]: Minimum confidence score (0-100) for matching
  /// - [stabilityThreshold]: Minimum stability score (0-100) for groups
  /// - [invalidateInterval]: Time after which unstable groups are removed
  ReceiptOptimizer({
    int loopThreshold = 10,
    int sumConfirmationThreshold = 2,
    int maxCacheSize = 10,
    int confidenceThreshold = 75,
    int stabilityThreshold = 50,
    Duration invalidateInterval = const Duration(seconds: 1),
  }) : _thresholder = ReceiptThresholder(baseThreshold: confidenceThreshold),
       _loopThreshold = loopThreshold,
       _sumConfirmationThreshold = sumConfirmationThreshold,
       _maxCacheSize = maxCacheSize,
       _stabilityThreshold = stabilityThreshold,
       _invalidateInterval = invalidateInterval,
       _shouldInitialize = false,
       _needsRegrouping = false,
       _unchangedCount = 0;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() {
    _shouldInitialize = true;
  }

  /// Processes a receipt to improve its recognition quality.
  ///
  /// Applies various optimization strategies including:
  /// - Company name normalization
  /// - Sum validation and correction
  /// - Position grouping and confidence scoring
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt, {force = false}) {
    if (!_checkConvergence(receipt)) {
      return receipt;
    }

    _initializeIfNeeded();
    _updateCompanies(receipt);
    _updateSums(receipt);
    _optimizeCompany(receipt);
    _optimizeSum(receipt);
    _cleanupGroups();
    _resetOperations();
    _processPositions(receipt);
    _updateEntities(receipt);

    if (!force && receipt.isValid) {
      return receipt;
    } else {
      return _createOptimizedReceipt(receipt);
    }
  }

  void _initializeIfNeeded() {
    if (_shouldInitialize) {
      _groups.clear();
      _companies.clear();
      _sums.clear();
      _sumCandidates.clear();
      _orderStats.clear();
      _lastAngleRad = null;
      _lastAngleDeg = null;
      _shouldInitialize = false;
      _needsRegrouping = false;
      _unchangedCount = 0;
      _lastFingerprint = null;
    }
  }

  bool _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.value}:${p.price.value}')
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

  void _forceRegroup() {
    final allPositions = _groups.expand((g) => g.members).toList();
    _groups.clear();
    for (final position in allPositions) {
      _processPosition(position);
    }
  }

  void _updateCompanies(RecognizedReceipt receipt) {
    if (receipt.company != null) {
      _companies.add(receipt.company!);
    }

    if (_companies.length > _maxCacheSize) {
      _companies.removeAt(0);
    }
  }

  void _updateSums(RecognizedReceipt receipt) {
    if (receipt.sum != null) {
      _sums.add(receipt.sum!);

      final sumLabel = receipt.entities
          ?.whereType<RecognizedSumLabel>()
          .firstWhereOrNull(
            (label) =>
                (label.line.boundingBox.top - receipt.sum!.line.boundingBox.top)
                    .abs() <
                ReceiptConstants.boundingBoxBuffer,
          );

      if (sumLabel != null) {
        final candidate = _SumCandidate(
          label: sumLabel,
          sum: receipt.sum!,
          verticalDistance:
              (sumLabel.line.boundingBox.top -
                      receipt.sum!.line.boundingBox.top)
                  .abs()
                  .toInt(),
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
  }

  void _optimizeCompany(RecognizedReceipt receipt) {
    if (receipt.company == null && _companies.isNotEmpty) {
      final lastCompany = _companies.lastOrNull;
      if (lastCompany != null) {
        final mostFrequent =
            ReceiptNormalizer.sortByFrequency(
              _companies.map((c) => c.value).toList(),
            ).lastOrNull;
        receipt.company = lastCompany.copyWith(value: mostFrequent);
      }
    }
  }

  void _optimizeSum(RecognizedReceipt receipt) {
    if (receipt.sum == null && _sums.isNotEmpty) {
      final sum = ReceiptNormalizer.sortByFrequency(
        _sums.map((c) => c.formattedValue).toList(),
      );
      final parsed = ReceiptFormatter.parse(sum.last);

      if ((parsed - receipt.calculatedSum.value).abs() < 0.01) {
        receipt.sum = _sums.last.copyWith(value: parsed);
      }
    }
  }

  void _cleanupGroups() {
    if (_groups.length >= _maxCacheSize) {
      final now = DateTime.now();
      final removed = <RecognizedGroup>{};
      _groups.removeWhere((g) {
        final kill =
            now.difference(g.timestamp) >= _invalidateInterval &&
            g.stability < _stabilityThreshold;
        if (kill) removed.add(g);
        return kill;
      });
      // prune order stats for removed groups
      for (final g in removed) {
        _orderStats.remove(g);
        // also remove g from other groups' aboveCounts maps
        for (final s in _orderStats.values) {
          s.aboveCounts.remove(g);
        }
      }
    }
    final emptied = _groups.where((g) => g.members.isEmpty).toList();
    _groups.removeWhere((g) => g.members.isEmpty);
    for (final g in emptied) {
      _orderStats.remove(g);
      for (final s in _orderStats.values) {
        s.aboveCounts.remove(g);
      }
    }
  }

  void _resetOperations() {
    for (final group in _groups) {
      for (final position in group.members) {
        position.operation = Operation.none;
      }
    }
  }

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

    for (final position in receipt.positions) {
      if (isStableSumConfirmed) {
        final matchesStableSum =
            (position.price.value - stableSum.sum.value).abs() < 0.01;

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

    final bool sameTimestamp = group.members.any(
      (p) => position.timestamp == p.timestamp,
    );

    final effectiveThreshold = _thresholder.threshold;

    final shouldUseGroup =
        !sameTimestamp &&
        positionConfidence.confidence >= effectiveThreshold &&
        positionConfidence.confidence > currentBestConfidence;

    return _ConfidenceResult(
      productConfidence: positionConfidence.product.confidence,
      priceConfidence: positionConfidence.price.confidence,
      confidence: positionConfidence.confidence,
      shouldUseGroup: shouldUseGroup,
    );
  }

  void _createNewGroup(RecognizedPosition position) {
    final newGroup = RecognizedGroup(maxGroupSize: _maxCacheSize);
    position.group = newGroup;
    position.operation = Operation.added;
    newGroup.addMember(position);
    _groups.add(newGroup);
  }

  void _addToExistingGroup(RecognizedPosition position, RecognizedGroup group) {
    position.group = group;
    position.operation = Operation.updated;
    group.addMember(position);
  }

  RecognizedReceipt _createOptimizedReceipt(RecognizedReceipt receipt) {
    final stableGroups =
        _groups.where((g) => g.stability >= _stabilityThreshold).toList();

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

        mergedReceipt.positions.add(patched);
      }
    }

    mergedReceipt.company ??= receipt.company;
    mergedReceipt.sum ??= receipt.sum;
    mergedReceipt.sumLabel ??= receipt.sumLabel;

    _removeOutliersToMatchSum(mergedReceipt);
    _updateEntities(mergedReceipt);

    return mergedReceipt;
  }

  void _updateEntities(RecognizedReceipt receipt) {
    final angle = ReceiptSkewEstimator.estimateDegrees(receipt);
    final products = receipt.positions.map((p) => p.product);
    final prices = receipt.positions.map((p) => p.price);

    receipt.entities?.clear();
    if (receipt.company != null) {
      receipt.entities?.add(
        RecognizedCompany(
          value: receipt.company!.value,
          line: _copyTextLineWithAngle(receipt.company!.line, angle),
        ),
      );
    }
    receipt.entities?.addAll(
      products.map(
        (product) => RecognizedProduct(
          value: product.value,
          line: _copyTextLineWithAngle(product.line, angle),
        ),
      ),
    );
    receipt.entities?.addAll(
      prices.map(
        (price) => RecognizedPrice(
          value: price.value,
          line: _copyTextLineWithAngle(price.line, angle),
        ),
      ),
    );
    if (receipt.sum != null) {
      receipt.entities?.add(
        RecognizedSum(
          value: receipt.sum!.value,
          line: _copyTextLineWithAngle(receipt.sum!.line, angle),
        ),
      );
    }
    if (receipt.sumLabel != null) {
      receipt.entities?.add(
        RecognizedSumLabel(
          value: receipt.sumLabel!.value,
          line: _copyTextLineWithAngle(receipt.sumLabel!.line, angle),
        ),
      );
    }
  }

  TextLine _copyTextLineWithAngle(TextLine line, double angle) {
    return TextLine(
      text: line.text,
      elements: line.elements,
      boundingBox: line.boundingBox,
      recognizedLanguages: line.recognizedLanguages,
      cornerPoints: line.cornerPoints,
      confidence: line.confidence,
      angle: angle,
    );
  }

  void _removeOutliersToMatchSum(RecognizedReceipt receipt) {
    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);
  }

  bool _isConfirmedSumValid(
    _SumCandidate candidate,
    RecognizedReceipt receipt,
  ) {
    if (receipt.positions.length < 2) return false;

    final calculated = receipt.calculatedSum.value;
    return (candidate.sum.value - calculated).abs() < 0.01;
  }

  void _learnOrder(RecognizedReceipt receipt) {
    // 1) Estimate skew
    final angleDeg = ReceiptSkewEstimator.estimateDegrees(receipt);

    // 2) Deadband: treat tiny angles as "no skew"
    if (angleDeg.abs() < 0.5) {
      _lastAngleDeg = 0.0;
      _lastAngleRad = null; // mark as "no projection"
    } else {
      _lastAngleDeg = angleDeg;
      _lastAngleRad = angleDeg * math.pi / 180.0;
    }

    final angleRad = _lastAngleRad; // might be null if near-flat
    final cosA = angleRad != null ? math.cos(-angleRad) : null;
    final sinA = angleRad != null ? math.sin(-angleRad) : null;

    // 3) Helper that projects only if needed
    double projectedY(TextLine line) {
      final center = line.boundingBox.center;
      if (angleRad == null) return center.dy.toDouble(); // raw Y if near-flat
      return center.dx * sinA! + center.dy * cosA!;
    }

    // 4) Collect observed positions with projected Y
    final observed = <_Obs>[];
    for (final p in receipt.positions) {
      final g = p.group;
      if (g == null) continue;
      final y = projectedY(p.product.line);
      observed.add(_Obs(group: g, y: y, ts: p.timestamp));
    }
    if (observed.isEmpty) return;

    // 5) Sort by projected Y
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

    // 6) Pairwise votes
    for (int i = 0; i < observed.length; i++) {
      for (int j = i + 1; j < observed.length; j++) {
        final a = observed[i].group;
        final b = observed[j].group;
        final sa = _orderStats[a]!;
        sa.aboveCounts[b] = (sa.aboveCounts[b] ?? 0) + 1;
      }
    }

    // decay/clamp vote totals once per scan
    for (final s in _orderStats.values) {
      final total = s.aboveCounts.values.fold<int>(0, (a, b) => a + b);
      if (total > 50) {
        s.aboveCounts.updateAll((_, v) => math.max(1, v ~/ 2));
      }
    }
  }

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

    // Fallbacks (unchanged)
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

  double _projectedYFromLine(TextLine line, double? angleRad) {
    final c = line.boundingBox.center;
    if (angleRad == null) return c.dy.toDouble(); // no projection
    final cosA = math.cos(-angleRad), sinA = math.sin(-angleRad);
    return c.dx * sinA + c.dy * cosA;
  }

  /// Releases all resources used by the optimizer.
  ///
  /// Clears all cached groups, companies, and sums.
  @override
  void close() {
    _groups.clear();
    _companies.clear();
    _sums.clear();
    _shouldInitialize = false;
  }
}

class _ConfidenceResult {
  final int productConfidence;
  final int priceConfidence;
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
      (sum.value - other.sum.value).abs() < 0.01;

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
