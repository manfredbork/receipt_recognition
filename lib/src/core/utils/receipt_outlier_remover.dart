import 'dart:math' as math;

import 'package:receipt_recognition/receipt_recognition.dart';

/// Static utility to remove outlier positions (wrong items, duplicates, metadata)
/// so that the calculated sum matches the detected receipt sum.
final class ReceiptOutlierRemover {
  static const int _tau = 1;
  static const int _maxCandidates = 12;
  static const int _lowConfidenceTake = 8;
  static const int _suspectExtraCap = 4;
  static const int _maxRemovals = 5;
  static const int _maxConfidenceForRemoval = 30;
  static const int _oppositeSignPenalty = 35;
  static const int _maxOppositeSignTake = 1;

  /// Entry point: modifies [receipt.positions] in-place when a valid outlier
  /// subset is found that fits the detected sum within [_tau] cents.
  static void removeOutliersToMatchSum(RecognizedReceipt receipt) {
    if (receipt.sum == null || receipt.positions.length <= 1) return;

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
    final delta = calculatedCents - detectedCents;
    if (delta == 0) return;

    final candidates = _buildCandidates(receipt);
    if (candidates.isEmpty) return;

    int? bestMask;
    _Best best = const _Best.none();
    for (var i = 0; i < candidates.length; i++) {
      final s = candidates[i].cents;
      final diff = (s - delta).abs();
      if (diff <= _tau) {
        best = _Best(count: 1, score: candidates[i].score, diffAbs: diff);
        bestMask = (1 << i);
        break;
      }
    }

    if (bestMask == null) {
      for (var i = 0; i < candidates.length; i++) {
        for (var j = i + 1; j < candidates.length; j++) {
          final s = candidates[i].cents + candidates[j].cents;
          final diff = (s - delta).abs();
          if (diff <= _tau) {
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
      if (removedCount > _maxRemovals) return;

      final minReach = removedSum + tailMinNeg[i];
      final maxReach = removedSum + tailMaxPos[i];
      if (delta < minReach - _tau || delta > maxReach + _tau) return;

      final curDiff = (removedSum - delta).abs();
      if (curDiff <= _tau) {
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

  static int _toCents(num v) => (v * 100).round();

  static int _signInt(int x) => x == 0 ? 0 : (x > 0 ? 1 : -1);

  static List<_Cand> _buildCandidates(RecognizedReceipt receipt) {
    final int deltaCents =
        _toCents(receipt.calculatedSum.value) - _toCents(receipt.sum!.value);

    final n = receipt.positions.length;
    if (n == 0) return const <_Cand>[];

    final need = _signInt(deltaCents);

    final preferred = <_Cand>[];
    final opposite = <_Cand>[];

    for (var i = 0; i < n; i++) {
      final pos = receipt.positions[i];
      final cents = _toCents(pos.price.value);
      final sgn = _signInt(cents);

      final conf = pos.confidence.clamp(0, 100);
      if (conf > _maxConfidenceForRemoval) continue;

      final suspect = _isSuspectKeyword(_safeProductText(pos));
      final baseScore = 100 - conf;
      var score = suspect ? baseScore + 50 : baseScore;

      if (need == 0 || sgn == need) {
        preferred.add(
          _Cand(
            index: i,
            cents: cents,
            confidence: conf,
            suspect: suspect,
            score: score,
          ),
        );
      } else {
        score -= _oppositeSignPenalty;
        opposite.add(
          _Cand(
            index: i,
            cents: cents,
            confidence: conf,
            suspect: suspect,
            score: score,
          ),
        );
      }
    }

    if (preferred.isEmpty && opposite.isEmpty) return const <_Cand>[];

    int takeFrom(List<_Cand> src, int limit, List<_Cand> out) {
      final byConf = [...src]
        ..sort((a, b) => a.confidence.compareTo(b.confidence));
      for (final r in byConf) {
        if (out.length >= limit) break;
        out.add(r);
      }
      final suspects =
          src
              .where((r) => r.suspect && !out.any((c) => c.index == r.index))
              .toList()
            ..sort((a, b) => b.score.compareTo(a.score));

      for (final r in suspects) {
        if (out.length >= limit + _suspectExtraCap) break;
        out.add(r);
      }
      return out.length;
    }

    final candidates = <_Cand>[];

    takeFrom(preferred, _lowConfidenceTake, candidates);

    if (_maxOppositeSignTake > 0 && candidates.length < _maxCandidates) {
      final room = math.min(
        _maxOppositeSignTake,
        _maxCandidates - candidates.length,
      );
      final added = <_Cand>[];
      takeFrom(opposite, room, added);
      candidates.addAll(added);
    }

    candidates.sort((a, b) {
      final byConf = a.confidence.compareTo(b.confidence);
      if (byConf != 0) return byConf;
      if (a.suspect != b.suspect) return a.suspect ? -1 : 1;
      return b.cents.abs().compareTo(a.cents.abs());
    });

    if (candidates.length > _maxCandidates) {
      candidates.removeRange(_maxCandidates, candidates.length);
    }
    return candidates;
  }

  static bool _isSuspectKeyword(String s) {
    final t = s.toLowerCase();
    return t.contains('summe') ||
        t.contains('gesamt') ||
        t.contains('mwst') ||
        t.contains('ust') ||
        t.contains('steuer') ||
        t.contains('bar') ||
        t.contains('ec') ||
        t.contains('karte') ||
        t.contains('zahlung') ||
        t.contains('wechsel') ||
        t.contains('iban') ||
        t.contains('gutschein') ||
        t.contains('rabatt') ||
        t.contains('rückgeld');
  }

  static String _safeProductText(RecognizedPosition p) {
    try {
      final v = p.product.value;
      return v;
    } catch (_) {
      return '';
    }
  }
}

/// small private record for candidate bookkeeping
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

/// small private struct to compare solutions
class _Best {
  final int count;
  final int score;
  final int diffAbs;

  const _Best({
    required this.count,
    required this.score,
    required this.diffAbs,
  });

  const _Best.none() : count = 1 << 30, score = -1, diffAbs = 1 << 30;

  bool betterThan(_Best other) {
    if (count != other.count) return count < other.count;
    if (score != other.score) return score > other.score;
    return diffAbs < other.diffAbs;
  }
}
