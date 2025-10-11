part of 'receipt_optimizer.dart';

/// Private helpers that maintain/trim groups and compute eviction scores.
extension _ReceiptGroupMaintenanceExt on ReceiptOptimizer {
  /// Best price (from the highest-confidence member) of a group.
  double _groupBestPrice(RecognizedGroup g) {
    final best = maxBy(g.members, (p) => p.confidence);
    return best?.price.value.toDouble() ?? 0.0;
  }

  /// Returns whether [g] should be removed based on age/strength and [trigger].
  ///
  /// When [trigger] is true (e.g., over capacity or sum is overinflated),
  /// a group is removed if it is either too old **or** too weak.
  /// Otherwise both conditions must be true.
  bool _shouldKillGroup(RecognizedGroup g, DateTime now, bool trigger) {
    final age = now.difference(g.timestamp);
    final tooOld = age >= _invalidateInterval;
    final tooWeak =
        g.stability < _stabilityThreshold ||
        g.confidence < _confidenceThreshold;
    return trigger ? (tooOld || tooWeak) : (tooOld && tooWeak);
  }

  /// Eviction score used when over capacity; higher scores are evicted first.
  ///
  /// Weighs age twice as much as weakness and adds a tiny stable tiebreaker
  /// based on group index to keep sort deterministic.
  double _evictScore(RecognizedGroup g, DateTime now) {
    final isOld = now.difference(g.timestamp) >= _invalidateInterval ? 1 : 0;
    final weakStab = g.stability < _stabilityThreshold ? 1 : 0;
    final weakConf = g.confidence < _confidenceThreshold ? 1 : 0;
    return isOld * 2 + weakStab + weakConf + (_groups.indexOf(g) * 1e-6);
  }
}
