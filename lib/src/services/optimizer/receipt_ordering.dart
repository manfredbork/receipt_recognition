part of 'receipt_optimizer.dart';

/// Observation of a group's vertical position at a given time.
final class _Obs {
  /// The group being observed.
  final RecognizedGroup group;

  /// Projected Y coordinate (skew-aware).
  final double y;

  /// Timestamp of the observation.
  final DateTime ts;

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

  _OrderStats({required this.firstSeen});
}

/// Private ordering helpers that need access to `ReceiptOptimizer` internals.
extension _ReceiptOrderingExt on ReceiptOptimizer {
  /// Projects a line’s center onto Y using an optional skew angle.
  double _projectedYFromLine(TextLine line, double? angleRad) {
    final c = line.boundingBox.center;
    if (angleRad == null) return c.dy.toDouble();
    final cosA = math.cos(-angleRad), sinA = math.sin(-angleRad);
    return c.dx * sinA + c.dy * cosA;
  }

  /// Median projected Y for all members of [g].
  double _medianProjectedY(RecognizedGroup g) {
    if (g.members.isEmpty) return double.infinity;
    final ys =
        g.members
            .map((p) => _projectedYFromLine(p.product.line, _lastAngleRad))
            .toList()
          ..sort();
    return ys[ys.length ~/ 2];
  }

  /// Earliest timestamp in [ps], or epoch for empty lists.
  DateTime _earliestTimestamp(List<RecognizedPosition> ps) =>
      ps.isEmpty
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : ps.map((p) => p.timestamp).reduce((x, y) => x.isBefore(y) ? x : y);
}
