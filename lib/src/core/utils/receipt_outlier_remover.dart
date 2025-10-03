import 'dart:math' as math;

import 'package:receipt_recognition/receipt_recognition.dart';

/// Static utility to remove outlier positions (wrong items, duplicates, metadata)
/// so that the calculated sum matches the detected receipt sum.
final class ReceiptOutlierRemover {
  /// Modifies [RecognizedReceipt.positions] in-place by removing a minimal subset of items
  /// whose total (±ReceiptConstants.outlierTau cents) closes the gap between calculated and detected sum.
  static void removeOutliersToMatchSum(RecognizedReceipt receipt) {
    if (receipt.sum == null || receipt.positions.length <= 1) return;

    final maxRemovals = receipt.positions.length / 4;
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

    final candidates = _rankPool(
      _selectPool(receipt, deltaCents, useDeltaGate: true),
    );

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

    int inGroupCmp(_Cand a, _Cand b) {
      final byConf = a.confidence.compareTo(b.confidence);
      if (byConf != 0) return byConf;
      if (a.suspect != b.suspect) return a.suspect ? -1 : 1;
      return b.cents.abs().compareTo(a.cents.abs());
    }

    for (final g in byPrice.values) {
      g.sort(inGroupCmp);
    }

    final groupKeys =
        byPrice.keys.toList()..sort((x, y) {
          final ax = byPrice[x]!.first;
          final ay = byPrice[y]!.first;
          final byConf = ax.confidence.compareTo(ay.confidence);
          if (byConf != 0) return byConf;
          if (ax.suspect != ay.suspect) return ax.suspect ? -1 : 1;
          return ay.cents.abs().compareTo(ax.cents.abs());
        });

    final ranked = <_Cand>[];
    int depth = 0;
    while (ranked.length < ReceiptConstants.outlierMaxCandidates) {
      bool progressed = false;
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

    final m = candidates.length;
    final tailMaxPos = List<int>.filled(m + 1, 0);
    final tailMinNeg = List<int>.filled(m + 1, 0);
    for (int i = m - 1; i >= 0; i--) {
      final v = candidates[i].cents;
      tailMaxPos[i] = tailMaxPos[i + 1] + (v > 0 ? v : 0);
      tailMinNeg[i] = tailMinNeg[i + 1] + (v < 0 ? v : 0);
    }

    void dfs(
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
      dfs(
        i + 1,
        removedCount + 1,
        removedSum + c.cents,
        removedScore + c.score,
        mask | (1 << i),
      );
      dfs(i + 1, removedCount, removedSum, removedScore, mask);
    }

    if (bestMask == null) {
      dfs(0, 0, 0, 0, 0);
    }
    if (bestMask == null) return;

    final n = receipt.positions.length;
    final hardCap = n - 1;
    int softCap;
    if (n <= 1) {
      softCap = 0;
    } else if (n <= 3) {
      softCap = 1;
    } else {
      softCap = math.max((n * 0.3).floor(), 2);
    }

    final allowedDeletions = math.min(hardCap, softCap);
    final positions = receipt.positions;
    final toRemove = <RecognizedPosition>{};
    int bits = bestMask!;
    int idx = 0;
    while (bits != 0) {
      if ((bits & 1) != 0) {
        toRemove.add(positions[candidates[idx].index]);
      }
      bits >>= 1;
      idx++;
    }

    if (toRemove.length > allowedDeletions) return;
    receipt.positions.removeWhere((p) => toRemove.contains(p));
  }

  /// Converts a numeric amount to integer cents (rounded).
  static int _toCents(num v) => (v * 100).round();

  /// Selects potential removal candidates based on confidence, probes, and delta.
  static List<_Cand> _selectPool(
    RecognizedReceipt receipt,
    int deltaCents, {
    required bool useDeltaGate,
  }) {
    if (receipt.sum == null) return const <_Cand>[];

    final pool = <_Cand>[];
    for (var i = 0; i < receipt.positions.length; i++) {
      final pos = receipt.positions[i];
      final cents = _toCents(pos.price.value);
      if (useDeltaGate && cents > deltaCents + ReceiptConstants.outlierTau) {
        continue;
      }
      if (cents <= 0) continue;

      final prodConf = pos.product.confidence;
      final effConf = (pos.confidence > prodConf) ? pos.confidence : prodConf;
      final alts = pos.product.alternativeTexts;

      if (effConf > ReceiptConstants.outlierLowConfThreshold &&
          alts.length > ReceiptConstants.outlierMinSamples) {
        continue;
      }

      final suspect = _isSuspectKeyword(_safeProductText(pos));
      final score =
          (100 - effConf) +
          (suspect ? ReceiptConstants.outlierSuspectBonus : 0);

      pool.add(
        _Cand(
          index: i,
          cents: cents,
          confidence: effConf,
          suspect: suspect,
          score: score,
        ),
      );
    }
    return pool;
  }

  /// Ranks candidates: lower confidence first, then suspects, then larger impact; caps to ReceiptConstants.outlierMaxCandidates.
  static List<_Cand> _rankPool(List<_Cand> pool) {
    if (pool.isEmpty) return const <_Cand>[];
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

  /// Heuristic: returns true if [s] looks like a sum/label keyword.
  static bool _isSuspectKeyword(String s) {
    return ReceiptPatterns.sumLabels.hasMatch(s);
  }

  /// Safely returns product text for a position or empty string on error.
  static String _safeProductText(RecognizedPosition p) {
    try {
      final v = p.product.value;
      return v;
    } catch (_) {
      return '';
    }
  }
}

/// Candidate record: index in positions, value in cents, and ranking features.
class _Cand {
  final int index;
  final int cents;
  final int confidence;
  final bool suspect;
  final int score;

  const _Cand({
    required this.index,
    required this.cents,
    required this.confidence,
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
