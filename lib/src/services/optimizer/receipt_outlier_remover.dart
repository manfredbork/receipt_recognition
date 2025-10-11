import 'dart:math' as math;

import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';
import 'package:receipt_recognition/src/utils/logging/index.dart';

/// Static utility to remove outlier positions (wrong items, duplicates, metadata)
/// so that the calculated sum matches the detected receipt sum.
final class ReceiptOutlierRemover {
  /// Modifies [RecognizedReceipt.positions] in-place by removing a minimal subset of items
  /// whose total (±ReceiptConstants.outlierTau cents) closes the gap between calculated and detected sum.
  static void removeOutliersToMatchSum(RecognizedReceipt receipt) {
    if (receipt.sum == null || receipt.positions.length <= 1) return;

    final maxRemovals =
        receipt.positions.length * ReceiptConstants.heuristicQuarter;
    final detectedSum = receipt.sum!.value.toDouble();
    final calculatedSum = receipt.calculatedSum.value.toDouble();

    final prices =
        receipt.positions.map((p) => p.price.value.toDouble()).toList();
    final negatives = prices.where((p) => p < 0.0);
    final positives = prices.where((p) => p >= 0.0);
    final negativeSum =
        negatives.isEmpty ? 0.0 : negatives.reduce((a, b) => a + b);
    final positiveSum =
        positives.isEmpty ? 0.0 : positives.reduce((a, b) => a + b);

    if (calculatedSum - negativeSum < detectedSum ||
        calculatedSum - positiveSum > detectedSum) {
      return;
    }

    final detectedCents = _toCents(detectedSum);
    final calculatedCents = _toCents(calculatedSum);
    final deltaCents = calculatedCents - detectedCents;

    ReceiptLogger.log('out.start', {
      'n': receipt.positions.length,
      'det': detectedSum,
      'calc': calculatedSum,
      'delta¢': deltaCents,
    });

    final candidates = List<_Cand>.of(
      _rankPool(_selectPool(receipt, deltaCents, useDeltaGate: true)),
    );

    ReceiptLogger.log('out.candidates', {
      'c':
          candidates
              .map(
                (c) => {
                  'i': c.index,
                  '¢': c.cents,
                  'conf': c.confidence,
                  'stab': c.stability,
                  'sus': c.suspect,
                  'score': c.score,
                },
              )
              .toList(),
    });

    if (candidates.isEmpty) {
      final fallback = _rankPool(
        _selectPool(receipt, deltaCents, useDeltaGate: false),
      );
      if (fallback.isEmpty) return;
      candidates.addAll(fallback);
    }

    final Map<int, List<_Cand>> byPrice = {};
    for (final c in candidates) {
      (byPrice[c.cents] ??= <_Cand>[]).add(c);
    }
    for (final g in byPrice.values) {
      g.sort(_inGroupCmp);
    }

    final groupKeys =
        byPrice.keys.toList()..sort((x, y) => _groupKeyCmp(byPrice, x, y));

    final ranked = <_Cand>[];
    var depth = 0;
    while (ranked.length < ReceiptConstants.outlierMaxCandidates) {
      var progressed = false;
      for (final k in groupKeys) {
        final g = byPrice[k]!;
        if (depth < g.length) {
          ranked.add(g[depth]);
          progressed = true;
          if (ranked.length >= ReceiptConstants.outlierMaxCandidates) break;
        }
      }
      if (!progressed) break;
      depth++;
    }

    candidates
      ..clear()
      ..addAll(ranked);

    int? bestMask;
    _Best best = const _Best.none();

    for (var i = 0; i < candidates.length; i++) {
      final s = candidates[i].cents;
      final diff = (s - deltaCents).abs();
      if (diff <= ReceiptConstants.outlierTau) {
        best = _Best(count: 1, score: candidates[i].score, diffAbs: diff);
        bestMask = (1 << i);
        break;
      }
    }

    if (bestMask == null) {
      for (var i = 0; i < candidates.length; i++) {
        for (var j = i + 1; j < candidates.length; j++) {
          final s = candidates[i].cents + candidates[j].cents;
          final diff = (s - deltaCents).abs();
          if (diff <= ReceiptConstants.outlierTau) {
            final sc = candidates[i].score + candidates[j].score;
            final cur = _Best(count: 2, score: sc, diffAbs: diff);
            if (cur.betterThan(best)) {
              best = cur;
              bestMask = (1 << i) | (1 << j);
            }
          }
        }
      }
    }

    if (bestMask == null) {
      final dfs = _dfsSearchBestMask(
        candidates: candidates,
        deltaCents: deltaCents,
        maxRemovals: maxRemovals,
      );
      best = dfs.best;
      bestMask = dfs.mask;
    }

    if (bestMask == null) return;

    final n = receipt.positions.length;
    final hardCap = n - 1;
    final softCap = n <= 1 ? 0 : (n <= 3 ? 1 : math.max((n * 0.3).floor(), 2));
    final allowedDeletions = math.min(hardCap, softCap);

    ReceiptLogger.log('out.choice', {
      'bestMask': bestMask,
      'allowed': allowedDeletions,
    });

    final positions = receipt.positions;
    final toRemove = <RecognizedPosition>{};
    var bits = bestMask;
    var idx = 0;
    while (bits != 0) {
      if ((bits & 1) != 0) {
        toRemove.add(positions[candidates[idx].index]);
      }
      bits >>= 1;
      idx++;
    }

    final hasProtected = toRemove.any((pos) {
      final i = receipt.positions.indexOf(pos);
      final cand = candidates.firstWhere(
        (c) => c.index == i,
        orElse:
            () => _Cand(
              index: -1,
              cents: 0,
              confidence: 0,
              stability: 0,
              suspect: false,
              score: 0,
            ),
      );
      return !_dfsRemovableGuard(cand);
    });
    if (hasProtected) return;

    ReceiptLogger.log('out.removed', {
      'idx': toRemove.map((p) => receipt.positions.indexOf(p)).toList(),
    });

    if (toRemove.length > allowedDeletions) return;
    receipt.positions.removeWhere(toRemove.contains);
  }

  /// Converts a numeric amount to integer cents (rounded).
  static int _toCents(num v) => (v * 100).round();

  /// Selects potential removal candidates based on confidence, probes, and delta.
  static List<_Cand> _selectPool(
    RecognizedReceipt receipt,
    int deltaCents, {
    required bool useDeltaGate,
  }) {
    if (receipt.sum == null) return <_Cand>[];

    final pool = <_Cand>[];
    for (var i = 0; i < receipt.positions.length; i++) {
      final pos = receipt.positions[i];
      final cents = _toCents(pos.price.value);
      if (useDeltaGate && cents > deltaCents + ReceiptConstants.outlierTau) {
        continue;
      }
      if (cents <= 0) continue;

      final conf = pos.confidence;
      final stab = pos.stability;
      final alts = pos.product.alternativeTexts;

      if (conf > ReceiptConstants.outlierLowConfThreshold &&
          alts.length > ReceiptConstants.outlierMinSamples) {
        continue;
      }

      final suspect = _isSuspectKeyword(_safeProductText(pos));
      final score =
          (100 - conf) + (suspect ? ReceiptConstants.outlierSuspectBonus : 0);

      pool.add(
        _Cand(
          index: i,
          cents: cents,
          confidence: conf,
          stability: stab,
          suspect: suspect,
          score: score,
        ),
      );
    }
    return pool;
  }

  /// Ranks candidates: lower confidence first, then suspects, then larger impact;
  /// caps to [ReceiptConstants.outlierMaxCandidates].
  static List<_Cand> _rankPool(List<_Cand> pool) {
    if (pool.isEmpty) return <_Cand>[];
    pool.sort((a, b) {
      final byConf = a.confidence.compareTo(b.confidence);
      if (byConf != 0) return byConf;
      if (a.suspect != b.suspect) return a.suspect ? -1 : 1;
      return b.cents.abs().compareTo(a.cents.abs());
    });
    if (pool.length > ReceiptConstants.outlierMaxCandidates) {
      return pool.sublist(0, ReceiptConstants.outlierMaxCandidates);
    }
    return pool;
  }

  /// Returns true if [c] is allowed to be removed by DFS.
  ///
  /// Blocks items that are BOTH high-confidence and high-stability,
  /// using stricter guards derived from optimizer thresholds.
  static bool _dfsRemovableGuard(_Cand c) {
    final confGuard = math.max(
      ReceiptConstants.optimizerConfidenceThreshold + 15,
      85,
    );
    final stabGuard = math.max(
      ReceiptConstants.optimizerStabilityThreshold + 15,
      75,
    );
    final highConf = c.confidence >= confGuard;
    final highStab = c.stability >= stabGuard;
    return !(highConf && highStab);
  }

  /// True if [s] looks like a sum/label keyword.
  static bool _isSuspectKeyword(String s) =>
      ReceiptPatterns.sumLabels.hasMatch(s);

  /// Safely returns product text for a position or empty string on error.
  static String _safeProductText(RecognizedPosition p) {
    try {
      return p.product.value;
    } catch (_) {
      return '';
    }
  }

  /// Comparator for candidates in the same price group.
  static int _inGroupCmp(_Cand a, _Cand b) {
    final byConf = a.confidence.compareTo(b.confidence);
    if (byConf != 0) return byConf;
    if (a.suspect != b.suspect) return a.suspect ? -1 : 1;
    return b.cents.abs().compareTo(a.cents.abs());
  }

  /// Comparator for group keys based on each group's top candidate.
  static int _groupKeyCmp(Map<int, List<_Cand>> byPrice, int x, int y) {
    final ax = byPrice[x]!.first;
    final ay = byPrice[y]!.first;
    final byConf = ax.confidence.compareTo(ay.confidence);
    if (byConf != 0) return byConf;
    if (ax.suspect != ay.suspect) return ax.suspect ? -1 : 1;
    return ay.cents.abs().compareTo(ax.cents.abs());
  }

  /// Bounded DFS with pruning to find a mask whose sum is within tolerance of [deltaCents].
  ///
  /// Includes a guard to forbid selecting candidates that are BOTH high-confidence
  /// and high-stability.
  static _DfsResult _dfsSearchBestMask({
    required List<_Cand> candidates,
    required int deltaCents,
    required num maxRemovals,
  }) {
    _Best best = const _Best.none();
    int? bestMask;

    final m = candidates.length;

    final tailMaxPos = List<int>.filled(m + 1, 0);
    final tailMinNeg = List<int>.filled(m + 1, 0);
    for (var i = m - 1; i >= 0; i--) {
      final v = candidates[i].cents;
      tailMaxPos[i] = tailMaxPos[i + 1] + (v > 0 ? v : 0);
      tailMinNeg[i] = tailMinNeg[i + 1] + (v < 0 ? v : 0);
    }

    void step(
      int i,
      int removedCount,
      int removedSum,
      int removedScore,
      int mask,
    ) {
      if (removedCount > maxRemovals) return;

      final minReach = removedSum + tailMinNeg[i];
      final maxReach = removedSum + tailMaxPos[i];
      if (deltaCents < minReach - ReceiptConstants.outlierTau ||
          deltaCents > maxReach + ReceiptConstants.outlierTau) {
        return;
      }

      final curDiff = (removedSum - deltaCents).abs();
      if (curDiff <= ReceiptConstants.outlierTau) {
        final cur = _Best(
          count: removedCount,
          score: removedScore,
          diffAbs: curDiff,
        );
        if (cur.betterThan(best)) {
          best = cur;
          bestMask = mask;
        }
      }
      if (i >= m) return;

      final c = candidates[i];

      if (_dfsRemovableGuard(c)) {
        step(
          i + 1,
          removedCount + 1,
          removedSum + c.cents,
          removedScore + c.score,
          mask | (1 << i),
        );
      }

      step(i + 1, removedCount, removedSum, removedScore, mask);
    }

    step(0, 0, 0, 0, 0);
    return _DfsResult(best, bestMask);
  }
}

/// Result of the bounded DFS: the best solution summary and its bitmask.
class _DfsResult {
  final _Best best;
  final int? mask;

  const _DfsResult(this.best, this.mask);
}

/// Candidate record: index in positions, value in cents, and ranking features.
class _Cand {
  final int index;
  final int cents;
  final int confidence;
  final int stability;
  final bool suspect;
  final int score;

  const _Cand({
    required this.index,
    required this.cents,
    required this.confidence,
    required this.stability,
    required this.suspect,
    required this.score,
  });
}

/// Solution quality summary used to compare candidate subsets.
class _Best {
  final int count;
  final int score;
  final int diffAbs;

  const _Best({
    required this.count,
    required this.score,
    required this.diffAbs,
  });

  /// Sentinel “worst” value to simplify comparisons.
  const _Best.none() : count = 1 << 30, score = -1, diffAbs = 1 << 30;

  /// Returns true if this solution is preferred over [other].
  bool betterThan(_Best other) {
    if (count != other.count) return count < other.count;
    if (score != other.score) return score > other.score;
    return diffAbs < other.diffAbs;
  }
}
