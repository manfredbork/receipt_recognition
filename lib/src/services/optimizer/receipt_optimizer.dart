import 'dart:math';

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
  RecognizedReceipt optimize(
    RecognizedReceipt receipt,
    ReceiptOptions options, {
    bool singleScan = true,
  });

  /// Public entry to finalize and reconcile a manually accepted receipt.
  void accept(RecognizedReceipt receipt, ReceiptOptions options);

  /// Resets resources used by the optimizer.
  void reset();

  /// Releases resources used by the optimizer.
  void close();
}

/// Default implementation of receipt optimizer that uses confidence scoring and grouping.
///
/// Groups similar positions across frames, stabilizes values, reconciles to totals,
/// and produces an ordered, merged receipt snapshot.
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

  /// Internal convergence bookkeeping.
  int _unchangedCount = 0;

  /// Whether a full reinit is needed.
  bool _shouldInitialize = false;

  /// Whether we should force a regroup step.
  bool _needsRegrouping = false;

  /// True if a store was detected in the current frame.
  bool _detectedStoreThisFrame = false;

  /// True if a total label was detected in the current frame.
  bool _detectedTotalLabelThisFrame = false;

  /// True if a total was detected in the current frame.
  bool _detectedTotalThisFrame = false;

  /// True if a purchase date was detected in the current frame.
  bool _detectedPurchaseDateThisFrame = false;

  /// Last fingerprint to detect stalling.
  String? _lastFingerprint;

  /// Shorthand for the active options provided by [ReceiptRuntime].
  static ReceiptOptions get _options => ReceiptRuntime.options;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() => _shouldInitialize = true;

  /// Processes a receipt and returns an optimized version driven by [options] tuning.
  ///
  /// When [singleScan] is true, cross-frame stabilization heuristics are relaxed.
  @override
  RecognizedReceipt optimize(
    RecognizedReceipt receipt,
    ReceiptOptions options, {
    bool singleScan = true,
  }) {
    return ReceiptRuntime.runWithOptions(options, () {
      _initializeIfNeeded();
      _resetFrameFreshness();
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
      _maybeMergeSimilarGroups(receipt);
      _suppressGenericBrandGroups();
      _resetOperations();
      _processPositions(receipt);
      _reconcileToTotal(receipt, singleScan);
      _applySkewAngle(receipt);
      _updateEntities(receipt);

      return _createOptimizedReceipt(receipt, singleScan: singleScan);
    });
  }

  /// Accepts a receipt manually and finalizes reconciliation if needed.
  @override
  void accept(RecognizedReceipt receipt, ReceiptOptions options) {
    ReceiptRuntime.runWithOptions(options, () {
      _processPositions(receipt);
      _reconcileToTotal(receipt, true);
      _applySkewAngle(receipt);
      _updateEntities(receipt);
    });
  }

  /// Resets all resources used by the optimizer.
  @override
  void reset() {
    _shouldInitialize = true;
    _initializeIfNeeded();
    _resetFrameFreshness();
  }

  /// Releases all resources used by the optimizer.
  @override
  void close() {
    reset();
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

  /// Resets per-frame detection flags for freshness tracking.
  void _resetFrameFreshness() {
    _detectedStoreThisFrame = false;
    _detectedTotalLabelThisFrame = false;
    _detectedTotalThisFrame = false;
    _detectedPurchaseDateThisFrame = false;
  }

  /// Tracks convergence to avoid infinite loops and trigger regrouping.
  void _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.normalizedText}:${p.price.value}')
        .join(',');
    final totalHash = receipt.total?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$totalHash';

    final loopThreshold = _options.tuning.optimizerLoopThreshold;

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
    _detectedStoreThisFrame = store != null;
    if (store != null) _stores.add(store);
    _trimCache(_stores);
  }

  /// Updates totals history cache for later normalization.
  void _updateTotals(RecognizedReceipt receipt) {
    final total = receipt.total;
    _detectedTotalThisFrame = total != null;
    if (total != null) _totals.add(total);
    _trimCache(_totals);
  }

  /// Updates total labels history cache for later normalization.
  void _updateTotalLabels(RecognizedReceipt receipt) {
    final totalLabel = receipt.totalLabel;
    _detectedTotalLabelThisFrame = totalLabel != null;
    if (totalLabel != null) _totalLabels.add(totalLabel);
    _trimCache(_totalLabels);
  }

  /// Updates purchase dates history cache for later normalization.
  void _updatePurchaseDates(RecognizedReceipt receipt) {
    final purchaseDate = receipt.purchaseDate;
    _detectedPurchaseDateThisFrame = purchaseDate != null;
    if (purchaseDate != null) _purchaseDates.add(purchaseDate);
    _trimCache(_purchaseDates);
  }

  /// Trims a cache list to the configured precision size.
  void _trimCache(List list) {
    final maxCacheSize = _options.tuning.optimizerMaxCacheSize;
    while (list.length > maxCacheSize) {
      list.removeAt(0);
    }
  }

  /// Fills store with the most frequent value in history.
  void _optimizeStore(RecognizedReceipt receipt) {
    if (_stores.isEmpty) return;
    final most =
        ReceiptNormalizer.sortByFrequency(
          _stores.map((c) => c.value).toList(),
        ).last;
    final last = _stores.last;

    if (last.value == most) {
      receipt.store =
          _detectedStoreThisFrame
              ? last
              : last.copyWith(line: ReceiptTextLine(text: last.line.text));
    } else {
      final best = _stores.lastWhere((s) => s.value == most);
      receipt.store = best.copyWith(
        line: ReceiptTextLine(text: best.line.text),
      );
    }
  }

  /// Fills total label with the most frequent value in history.
  void _optimizeTotalLabel(RecognizedReceipt receipt) {
    if (_totalLabels.isEmpty) return;
    final most =
        ReceiptNormalizer.sortByFrequency(
          _totalLabels.map((c) => c.value).toList(),
        ).last;
    final last = _totalLabels.last;

    if (last.value == most) {
      receipt.totalLabel =
          _detectedTotalLabelThisFrame
              ? last
              : last.copyWith(line: ReceiptTextLine(text: last.line.text));
    } else {
      final best = _totalLabels.lastWhere((s) => s.value == most);
      receipt.totalLabel = best.copyWith(
        line: ReceiptTextLine(text: best.line.text),
      );
    }
  }

  /// Fills total with the most frequent value in history.
  void _optimizeTotal(RecognizedReceipt receipt) {
    if (_totals.isEmpty) return;
    final most =
        ReceiptNormalizer.sortByFrequency(
          _totals.map((c) => c.formattedValue).toList(),
        ).last;
    final last = _totals.last;

    if (last.formattedValue == most) {
      receipt.total =
          _detectedTotalThisFrame
              ? last
              : last.copyWith(line: ReceiptTextLine(text: last.line.text));
    } else {
      final best = _totals.lastWhere((s) => s.formattedValue == most);
      receipt.total = best.copyWith(
        line: ReceiptTextLine(text: best.line.text),
      );
    }
  }

  /// Fills purchase date with the most frequent value in history.
  void _optimizePurchaseDate(RecognizedReceipt receipt) {
    if (_purchaseDates.isEmpty) return;
    final most =
        ReceiptNormalizer.sortByFrequency(
          _purchaseDates.map((c) => c.formattedValue).toList(),
        ).last;
    final last = _purchaseDates.last;

    if (last.formattedValue == most) {
      receipt.purchaseDate =
          _detectedPurchaseDateThisFrame
              ? last
              : last.copyWith(line: ReceiptTextLine(text: last.line.text));
    } else {
      final best = _purchaseDates.lastWhere((s) => s.formattedValue == most);
      receipt.purchaseDate = best.copyWith(
        line: ReceiptTextLine(text: best.line.text),
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

  /// Merges cross-frame groups that likely represent the same line item (never same-frame), before reconciliation.
  void _maybeMergeSimilarGroups(RecognizedReceipt receipt) {
    if (_groups.length < 2) return;

    final total = receipt.total?.value;
    final calc = receipt.calculatedTotal.value;
    final overshoot = (total == null) ? null : (calc - total);
    final shouldRun = total == null || overshoot! > 0.0;
    if (!shouldRun) return;

    final yTol = _dynamicYTolerancePx();

    final byPrice = <int, List<RecognizedGroup>>{};
    for (final g in _groups) {
      if (g.members.isEmpty) continue;
      final cents = _groupCents(g);
      (byPrice[cents] ??= []).add(g);
    }

    final toRemove = <RecognizedGroup>{};
    double plannedReduction = 0.0;

    for (final entry in byPrice.entries) {
      final gs = entry.value;
      if (gs.length < 2) continue;

      double scorePair(RecognizedGroup a, RecognizedGroup b) {
        if (_groupsCoOccur(a, b)) {
          final dy = (_groupY(a) - _groupY(b)).abs();
          if (dy > yTol) return 0.0;
        }
        final prodSim = ReceiptNormalizer.stringSimilarity(
          _groupBestText(a),
          _groupBestText(b),
        );
        final dy = (_groupY(a) - _groupY(b)).abs();
        final yClose = dy <= (prodSim >= 0.95 ? yTol * 1.25 : yTol);
        final okSupport = a.members.length >= 2 && b.members.length >= 2;
        if (!okSupport || !yClose || prodSim < 0.86) return 0.0;
        return 0.6 + 0.4 * prodSim;
      }

      final bestFor = <RecognizedGroup, (RecognizedGroup, double)>{};
      for (final g in gs) {
        var best = (null as RecognizedGroup?, 0.0);
        for (final h in gs) {
          if (identical(g, h)) continue;
          final s = scorePair(g, h);
          if (s > best.$2) best = (h, s);
        }
        if (best.$1 != null) bestFor[g] = (best.$1!, best.$2);
      }

      const mergeThresh = 0.7;
      final pairs = <(RecognizedGroup, RecognizedGroup, double)>[];
      for (final g in gs) {
        final bg = bestFor[g];
        if (bg == null) continue;
        final h = bg.$1;
        final bh = bestFor[h];
        if (bh == null) continue;
        final force = bg.$2 >= 0.95 && bh.$2 >= 0.95;
        if ((identical(bh.$1, g) &&
                bg.$2 >= mergeThresh &&
                bh.$2 >= mergeThresh) ||
            force) {
          final a = _groups.indexOf(g) < _groups.indexOf(h) ? g : h;
          final b = identical(a, g) ? h : g;
          pairs.add((a, b, (bg.$2 + bh.$2) * 0.5));
        }
      }

      final seen = <Set<RecognizedGroup>>{};
      final uniquePairs = <(RecognizedGroup, RecognizedGroup, double)>[];
      for (final p in pairs) {
        final key = {p.$1, p.$2};
        if (seen.add(key)) uniquePairs.add(p);
      }
      uniquePairs.sort((x, y) => y.$3.compareTo(x.$3));

      for (final (a, b, _) in uniquePairs) {
        if (toRemove.contains(a) || toRemove.contains(b)) continue;

        if (overshoot != null) {
          final reduc = entry.key / 100.0;
          if (plannedReduction + reduc >
              overshoot + _options.tuning.optimizerTotalTolerance) {
            break;
          }
          plannedReduction += reduc;
        }

        for (final p in b.members) {
          p.group = a;
          a.addMember(p);
        }
        toRemove.add(b);

        _orderStats.remove(b);
        for (final s in _orderStats.values) {
          s.aboveCounts.remove(b);
        }
      }
    }

    if (toRemove.isNotEmpty) _purgeGroups(toRemove);
  }

  /// Drops brand-only groups that are token-subsets of a nearby, more specific group at the same price.
  void _suppressGenericBrandGroups() {
    if (_groups.length < 2) return;

    final yTol = _dynamicYTolerancePx();

    final byPrice = <int, List<RecognizedGroup>>{};
    for (final g in _groups) {
      if (g.members.isEmpty) continue;
      final c = _groupCents(g);
      (byPrice[c] ??= []).add(g);
    }

    final toRemove = <RecognizedGroup>{};

    for (final entry in byPrice.entries) {
      final gs = entry.value;
      if (gs.length < 2) continue;

      final tokens = <RecognizedGroup, Set<String>>{};
      final spec = <RecognizedGroup, int>{};
      final ymap = <RecognizedGroup, double>{};

      for (final g in gs) {
        final t = _groupBestText(g);
        tokens[g] = ReceiptNormalizer.tokensForMatch(t);
        spec[g] = ReceiptNormalizer.specificity(t);
        ymap[g] = _groupY(g);
      }

      for (int i = 0; i < gs.length; i++) {
        for (int j = i + 1; j < gs.length; j++) {
          final a = gs[i], b = gs[j];
          final ya = ymap[a]!, yb = ymap[b]!;
          if ((ya - yb).abs() > yTol) continue;

          final ta = tokens[a]!, tb = tokens[b]!;
          final aSubset =
              ta.isNotEmpty &&
              ta.difference(tb).isEmpty &&
              tb.length > ta.length;
          final bSubset =
              tb.isNotEmpty &&
              tb.difference(ta).isEmpty &&
              ta.length > tb.length;

          if (aSubset && (spec[a]! + 5 < spec[b]!)) toRemove.add(a);
          if (bSubset && (spec[b]! + 5 < spec[a]!)) toRemove.add(b);
        }
      }
    }

    if (toRemove.isEmpty) return;
    _purgeGroups(toRemove);
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

  /// Returns the median of the given numeric values.
  double _median(List<double> values) {
    if (values.isEmpty) return double.nan;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) {
      return sorted[mid];
    } else {
      return (sorted[mid - 1] + sorted[mid]) / 2.0;
    }
  }

  /// Filters out column outliers based on deviation from the median x coordinate using MAD.
  List<Point<double>> _filterColumnOutliers(
    List<Point<double>> pts, {
    double k = 3.5,
  }) {
    if (pts.length <= 3) return pts;

    final xs = pts.map((p) => p.y).toList();

    final medianX = _median(xs);
    final deviations = xs.map((x) => (x - medianX).abs()).toList();
    final mad = _median(deviations);

    if (mad == 0) return pts;

    final threshold = k * mad;
    final filtered = <Point<double>>[];

    for (var i = 0; i < pts.length; i++) {
      if (deviations[i] <= threshold) {
        filtered.add(pts[i]);
      }
    }

    return filtered;
  }

  /// Estimates the receipt skew angle from product-column left edges.
  /// Computes a robust skew per frame (timestamp) and aggregates across frames.
  /// Stores the final skew in degrees in receipt.bounds.skewAngle.
  void _applySkewAngle(RecognizedReceipt receipt) {
    final pos = receipt.positions;
    if (pos.length < 2) return;

    final byTs = <int, List<RecognizedPosition>>{};
    for (final p in pos) {
      final ts = p.timestamp.millisecondsSinceEpoch;
      (byTs[ts] ??= []).add(p);
    }

    final skews = <double>[];
    final weights = <double>[];

    for (final entry in byTs.entries) {
      final ps = entry.value;
      if (ps.length < 2) continue;

      final pts = <Point<double>>[];
      for (final p in ps) {
        final a = p.product.line.boundingBox;
        final yCenter = a.center.dy;
        final xLeft = a.left;
        pts.add(Point<double>(yCenter, xLeft));
      }

      if (pts.length < 2) continue;

      final filtered = _filterColumnOutliers(pts);
      if (filtered.length < 2) continue;

      final slope = _theilSenSlopeXvsY(filtered);
      final skewRad = _wrapAngle(atan(slope));
      final skewDeg = skewRad * 180 / pi;

      if (!skewDeg.isFinite) continue;
      if (skewDeg.abs() > 25.0) continue;

      skews.add(skewDeg);
      weights.add(filtered.length.toDouble());
    }

    if (skews.isEmpty) return;

    double finalSkewDeg;
    if (skews.length == 1) {
      finalSkewDeg = skews.first;
    } else {
      finalSkewDeg = _weightedMedian(skews, weights);
    }

    if (receipt.bounds != null) {
      receipt.bounds = receipt.bounds!.copyWith(skewAngle: finalSkewDeg);
    }

    ReceiptLogger.log('bounds.skew.per_frame', {
      'frames': skews.length,
      'skewDeg': finalSkewDeg,
      'minDeg': skews.reduce(min),
      'maxDeg': skews.reduce(max),
      'medAbs': _median(skews.map((e) => e.abs()).toList()),
    });
  }

  /// Returns the weighted median of values using the given weights.
  static double _weightedMedian(List<double> values, List<double> weights) {
    if (values.isEmpty) return 0.0;

    if (values.length != weights.length) {
      final sorted = [...values]..sort();
      return sorted[sorted.length >> 1];
    }

    final pairs = List.generate(values.length, (i) => (values[i], weights[i]));
    pairs.sort((a, b) => a.$1.compareTo(b.$1));

    double total = 0.0;
    for (final p in pairs) {
      final w = p.$2;
      if (w.isFinite && w > 0) total += w;
    }

    if (total <= 0.0) {
      final sorted = [...values]..sort();
      return sorted[sorted.length >> 1];
    }

    final half = total * 0.5;
    double acc = 0.0;

    for (final p in pairs) {
      final w = p.$2;
      if (!(w.isFinite && w > 0)) continue;
      acc += w;
      if (acc >= half) return p.$1;
    }

    return pairs.last.$1;
  }

  /// Theil–Sen slope (median of all pairwise slopes) for x vs y, using all pairs.
  double _theilSenSlopeXvsY(List<Point<double>> pts) {
    const eps = 1e-6;
    final n = pts.length;
    final slopes = <double>[];
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        final dy = pts[j].x - pts[i].x;
        if (dy.abs() < eps) continue;
        final dx = pts[j].y - pts[i].y;
        slopes.add(dx / dy);
      }
    }

    if (slopes.isEmpty) return 0.0;
    slopes.sort();
    return slopes[slopes.length >> 1];
  }

  /// Wraps an angle in radians to the range (-π, π].
  double _wrapAngle(double a) {
    const twopi = 2 * pi;
    while (a <= -pi) {
      a += twopi;
    }
    while (a > pi) {
      a -= twopi;
    }
    return a;
  }

  /// Assigns a position to the best existing group or creates a new one.
  void _processPosition(RecognizedPosition position) {
    int bestConf = 0;
    RecognizedGroup? bestGroup;

    for (final group in _groups) {
      final r = _calculateConfidence(position, group, bestConf);
      if (r.shouldUseGroup) {
        bestConf = r.confidence;
        bestGroup = group;
        position.product.confidence = r.productConfidence;
        position.price.confidence = r.priceConfidence;
      }
    }

    if (bestGroup == null) {
      _createNewGroup(position);
    } else {
      _addToExistingGroup(position, bestGroup);
    }

    ReceiptLogger.log('group.skip', {
      'pos': ReceiptLogger.posKey(position),
      'bestConf': bestConf,
    });
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

    final closeY = _isYCloseToGroup(position, group);
    final samePrice = _hasSamePriceInGroup(position, group);
    final thrNew = _options.tuning.optimizerConfidenceThreshold;
    final thrBase = (thrNew - 5).clamp(0, 100);
    final thr = (samePrice && closeY) ? (thrBase - 5).clamp(0, 100) : thrBase;

    final shouldUseGroup =
        !sameTimestamp &&
        positionConfidence.confidence >= thr &&
        positionConfidence.confidence > currentBestConfidence;

    ReceiptLogger.log('conf', {
      'pos': ReceiptLogger.posKey(position),
      'grp': ReceiptLogger.grpKey(group),
      'price': position.price.value,
      'prodC': productConfidence.value,
      'priceC': priceConfidence.value,
      'thr': thr,
      'use': shouldUseGroup,
      'why':
          sameTimestamp
              ? 'same-frame-same-line'
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

  /// Returns the group price in cents based on its highest-confidence member.
  int _groupCents(RecognizedGroup g) =>
      _toCents(maxBy(g.members, (p) => p.confidence)!.price.value);

  /// Returns the best normalized product text for a group.
  String _groupBestText(RecognizedGroup g) =>
      maxBy(g.members, (p) => p.confidence)!.product.normalizedText;

  /// Returns the learned Y or the median Y for a group.
  double _groupY(RecognizedGroup g) {
    final s = _orderStats[g];
    if (s != null && s.hasY) return s.orderY;
    return _medianProjectedY(g);
  }

  /// Returns true if two groups have any members from the same frame.
  bool _groupsCoOccur(RecognizedGroup a, RecognizedGroup b) =>
      a.members.any((p) => b.members.any((q) => p.timestamp == q.timestamp));

  /// Returns true if the position's Y is close to the group's learned Y (or median Y) within a dynamic tolerance.
  bool _isYCloseToGroup(RecognizedPosition pos, RecognizedGroup group) {
    final gy =
        _orderStats[group]?.hasY == true
            ? _orderStats[group]!.orderY
            : _medianProjectedY(group);
    if (!gy.isFinite) return false;
    final py = pos.product.line.boundingBox.center.dy;
    final tol = _dynamicYTolerancePx();
    return (py - gy).abs() <= tol;
  }

  /// Returns true if the position's price matches any member's price in the group (exact cents).
  bool _hasSamePriceInGroup(RecognizedPosition pos, RecognizedGroup group) {
    final cents = _toCents(pos.price.value);
    for (final m in group.members) {
      if (_toCents(m.price.value) == cents) return true;
    }
    return false;
  }

  /// Computes a dynamic vertical tolerance in pixels using the median line height across groups.
  double _dynamicYTolerancePx() {
    final hs = <double>[];
    for (final g in _groups) {
      for (final p in g.members) {
        hs.add(p.product.line.boundingBox.height);
      }
    }
    if (hs.isEmpty) return 6.0;
    hs.sort();
    final med = hs[hs.length ~/ 2];
    final clamped = med.clamp(4.0, 10.0);
    return clamped * 0.45;
  }

  /// Returns the median projected Y for a group's members (fallback when no learned Y exists).
  double _medianProjectedY(RecognizedGroup g) {
    if (g.members.isEmpty) return double.infinity;
    final ys =
        g.members.map((p) => p.product.line.boundingBox.center.dy).toList()
          ..sort();
    return ys[ys.length ~/ 2];
  }

  /// Creates a fresh group for the given position.
  void _createNewGroup(RecognizedPosition position) {
    final maxCacheSize = _options.tuning.optimizerMaxCacheSize;
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
    bool singleScan = false,
  }) {
    if (receipt.isValid && receipt.isConfirmed) return receipt;

    ReceiptLogger.log('opt.in', {
      'n': receipt.positions.length,
      'calc': receipt.calculatedTotal.value.toStringAsFixed(2),
      'total?': receipt.total?.value,
    });

    final halfStability = _options.tuning.optimizerStabilityThreshold ~/ 2;
    final halfCacheSize = ReceiptRuntime.tuning.optimizerMaxCacheSize ~/ 2;

    bool stable(stab, size) => stab >= halfStability && size >= halfCacheSize;

    final stableGroups =
        _groups
            .where((g) => stable(g.stability, g.members.length) || singleScan)
            .toList();

    _learnOrder(receipt);
    stableGroups.sort(_compareGroupsForOrder);

    final mergedReceipt = RecognizedReceipt.empty();
    final currentGroups = receipt.positions.map((p) => p.group);

    for (final group in stableGroups) {
      final best = maxBy(group.members, (p) => p.confidence);
      final latest = maxBy(group.members, (p) => p.timestamp);
      if (best == null || latest == null) continue;

      final patched = best.copyWith(
        product: best.product.copyWith(line: latest.product.line),
        price: best.price.copyWith(line: latest.price.line),
        group: best.group,
      )..operation = latest.operation;

      patched.product.position = patched;
      patched.price.position = patched;

      ReceiptLogger.log('merge.keep', {
        'grp': ReceiptLogger.grpKey(group),
        'pos': ReceiptLogger.posKey(patched),
        'bestC': best.confidence,
        'latestTs': latest.timestamp.millisecondsSinceEpoch,
      });

      if (receipt.isValid && !currentGroups.contains(group)) continue;

      mergedReceipt.positions.add(patched);
    }

    mergedReceipt.store = receipt.store ?? mergedReceipt.store;
    mergedReceipt.total = receipt.total ?? mergedReceipt.total;
    mergedReceipt.totalLabel = receipt.totalLabel ?? mergedReceipt.totalLabel;
    mergedReceipt.purchaseDate =
        receipt.purchaseDate ?? mergedReceipt.purchaseDate;
    mergedReceipt.bounds = receipt.bounds ?? mergedReceipt.bounds;

    _updateEntities(mergedReceipt);

    ReceiptLogger.log('opt.out', {
      'n': mergedReceipt.positions.length,
      'calc': mergedReceipt.calculatedTotal.value.toStringAsFixed(2),
      'total?': mergedReceipt.total?.value,
    });

    if (receipt.isValid && !mergedReceipt.isValid) {
      return receipt;
    }

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

  /// Reconciles the receipt to its declared total by dropping excess or, if enabled, adding pseudo position.
  void _reconcileToTotal(RecognizedReceipt receipt, bool pseudoPosition) {
    final total = receipt.total?.value;
    if (total == null) return;

    final tol = _options.tuning.optimizerTotalTolerance;
    final beforeLen = receipt.positions.length;

    receipt.positions.removeWhere(
      (pos) => (pos.price.value - total).abs() <= tol,
    );

    if (receipt.isValid || receipt.positions.isEmpty) return;

    final tolC = (tol * 100).round();
    final targetC = _toCents(total);
    final beforeC = _sumCents(receipt.positions);

    final removedAsTotal = beforeLen - receipt.positions.length;

    if (removedAsTotal > 0) {
      ReceiptLogger.log('recon.drop_total_like', {'removed': removedAsTotal});
    }

    int currentC = _sumCents(receipt.positions);

    final deltaC = currentC - targetC;
    if (deltaC.abs() < tolC) {
      ReceiptLogger.log('recon.within_tol', {
        'sum': currentC / 100.0,
        'target': targetC / 100.0,
        'tol': tol,
      });
      return;
    }

    if (deltaC > 0) {
      final int maxCandidates = beforeLen ~/ 2;

      int membersCompare(RecognizedPosition a, RecognizedPosition b) =>
          (a.group?.members.length ?? 0).compareTo(
            b.group?.members.length ?? 0,
          );

      final candidates = List<RecognizedPosition>.from(receipt.positions)
        ..sort(membersCompare);

      final pool = candidates.take(maxCandidates).toList();

      if (pool.length <= 1) return;

      final targetRemove = deltaC.abs();
      final toRemoveIdx = _pickSubsetToDrop(pool, targetRemove, beamWidth: 256);

      if (toRemoveIdx.length <= 1) {
        final beforeErr = (currentC - targetC).abs();
        for (final p in pool) {
          final after = currentC - _toCents(p.price.value);
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

    if (pseudoPosition) {
      final currentTotal = receipt.calculatedTotal.value;

      if (currentTotal - tol > total) {
        int priceCompare(RecognizedPosition a, RecognizedPosition b) =>
            a.price.value.compareTo(b.price.value);

        final candidates = List<RecognizedPosition>.from(receipt.positions)
          ..sort(priceCompare);

        final toRemove =
            candidates
                .where((pos) => currentTotal - pos.price.value >= total - tol)
                .firstOrNull;

        if (toRemove != null) {
          receipt.positions.remove(toRemove);
          toRemove.group?.members.remove(toRemove);
        }
      }

      if (receipt.isValid) return;

      final pseudoName = _options.tuning.optimizerUnrecognizedProductName;
      final position = RecognizedPosition.pseudo(receipt, pseudoName);
      _createNewGroup(position);
      receipt.positions.add(position);
    }
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
        final nw = min(s.worstC, conf);
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
    final alpha = _options.tuning.optimizerEwmaAlpha;
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

    final decayThreshold = _options.tuning.optimizerAboveCountDecayThreshold;
    for (final s in _orderStats.values) {
      final total = s.aboveCounts.values.fold<int>(0, (a, b) => a + b);
      if (total > decayThreshold) {
        s.aboveCounts.updateAll((_, v) => max(1, v ~/ 2));
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
    final tiePx = _options.tuning.optimizerTotalTolerance;

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
    final grace = Duration(seconds: 1);

    final staleForAWhile = now.difference(g.timestamp) >= grace;
    final veryWeak =
        g.stability < (_options.tuning.optimizerStabilityThreshold ~/ 2) &&
        g.confidence < (_options.tuning.optimizerConfidenceThreshold ~/ 2);
    final tiny = g.members.length <= 2;
    return staleForAWhile && veryWeak && tiny;
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
