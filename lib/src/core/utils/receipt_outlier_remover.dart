import 'dart:math' as math;

import 'package:receipt_recognition/receipt_recognition.dart';

/// Static utility to remove outlier positions (wrong items, duplicates, metadata)
/// so that the calculated sum matches the detected receipt sum.
final class ReceiptOutlierRemover {
  static const int _tau = 1;
  static const int _maxCandidates = 12;

  /// Entry point: modifies [receipt.positions] in-place when a valid outlier
  /// subset is found that fits the detected sum within [_tau] cents.
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
    final candidates = _buildCandidates(receipt, deltaCents);
    if (candidates.isEmpty) return;

    final Map<int, List<_Cand>> byPrice = {};
    for (final c in candidates) {
      (byPrice[c.cents] ??= <_Cand>[]).add(c);
    }

    int inGroupCmp(_Cand a, _Cand b) {
      final byConf = a.confidence.compareTo(b.confidence); // lower first
      if (byConf != 0) return byConf;
      if (a.suspect != b.suspect) return a.suspect ? -1 : 1; // suspect first
      return b.cents.abs().compareTo(a.cents.abs()); // larger |price| first
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
    while (ranked.length < _maxCandidates) {
      bool progressed = false;
      for (final k in groupKeys) {
        final g = byPrice[k]!;
        if (depth < g.length) {
          ranked.add(g[depth]);
          progressed = true;
          if (ranked.length >= _maxCandidates) break;
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
          final diff = (s - deltaCents).abs();
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
      if (removedCount > maxRemovals) return;

      final minReach = removedSum + tailMinNeg[i];
      final maxReach = removedSum + tailMaxPos[i];
      if (deltaCents < minReach - _tau || deltaCents > maxReach + _tau) return;

      final curDiff = (removedSum - deltaCents).abs();
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

  static List<_Cand> _buildCandidates(
    RecognizedReceipt receipt,
    int deltaCents,
  ) {
    if (receipt.sum == null) return const <_Cand>[];

    // Tunables for this selector (local to keep the function self-contained).
    const int lowConfThreshold = 35; // only touch items we don't trust much
    const int minSamples = 3; // need enough probes/observations
    final int tau = _tau; // cents tolerance (existing constant)

    // Gather positive-price, low-confidence, well-probed positions.
    final candidatesRaw = <_Cand>[];
    for (var i = 0; i < receipt.positions.length; i++) {
      final pos = receipt.positions[i];
      final cents = _toCents(pos.price.value);

      // Effective confidence = max(position, product) to be conservative.
      final effConf = math.max(pos.confidence, pos.product.confidence);

      // Probe count / consensus from alternative texts in the position's group.
      final alts = pos.product.alternativeTexts;

      if (effConf > lowConfThreshold && alts.length > minSamples) continue;

      // Optional delta-size gate: prefer items not wildly bigger than the gap.
      if (cents > deltaCents + tau) {
        // We'll allow falling back later if this gate becomes too restrictive.
        continue;
      }

      final suspect = _isSuspectKeyword(_safeProductText(pos));
      final score = (100 - effConf) + (suspect ? 50 : 0); // simple, monotone

      candidatesRaw.add(
        _Cand(
          index: i,
          cents: cents,
          confidence: effConf,
          suspect: suspect,
          score: score,
        ),
      );
    }

    // If the delta-size gate filtered everything, retry without that gate.
    List<_Cand> pool = candidatesRaw;
    if (pool.isEmpty) {
      for (var i = 0; i < receipt.positions.length; i++) {
        final pos = receipt.positions[i];
        final cents = _toCents(pos.price.value);
        if (cents <= 0) continue;

        final prodConf = pos.product.confidence;
        final effConf = (pos.confidence > prodConf) ? pos.confidence : prodConf;
        if (effConf > lowConfThreshold) continue;

        final suspect = _isSuspectKeyword(_safeProductText(pos));
        final score = (100 - effConf) + (suspect ? 50 : 0);

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
    }

    if (pool.isEmpty) return const <_Cand>[];

    // Rank: lowest confidence first, then suspects, then larger impact.
    pool.sort((a, b) {
      final byConf = a.confidence.compareTo(b.confidence); // lower is weaker
      if (byConf != 0) return byConf;
      if (a.suspect != b.suspect) return a.suspect ? -1 : 1;
      return b.cents.abs().compareTo(a.cents.abs()); // bigger helps reach delta
    });

    // Cap total number of candidates.
    if (pool.length > _maxCandidates) {
      pool = pool.sublist(0, _maxCandidates);
    }
    return pool;
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
