import 'package:receipt_recognition/src/services/parser/index.dart';

/// Dynamically adjusts confidence thresholds for position grouping
/// based on receipt sum feedback (recognized vs calculated).
///
/// Helps balance under- and over-grouping in adaptive receipt scanning.
final class ReceiptThresholder {
  /// Baseline confidence threshold (0–100).
  final int baseThreshold;

  /// Maximum allowed deviation from the baseline.
  final int maxDelta;

  /// Step size for each threshold adjustment.
  final int step;

  int _delta = 0;

  /// Creates a new adaptive thresholder with given parameters.
  ReceiptThresholder({
    this.baseThreshold = 75,
    this.maxDelta = 20,
    this.step = 5,
  }) : assert(baseThreshold >= 0 && baseThreshold <= 100),
       assert(maxDelta >= 0),
       assert(step > 0);

  /// Current threshold to use for grouping decisions (clamped to 0–100).
  int get threshold => _clampInt(baseThreshold + _delta, 0, 100);

  /// Resets the threshold back to the baseline.
  void reset() => _delta = 0;

  /// Updates the threshold based on comparison of recognized and calculated sums.
  ///
  /// If [recognizedSum] is `null` or within [ReceiptConstants.sumTolerance] of [calculatedSum],
  /// the dynamic delta is reset. Otherwise:
  /// - If calculated > recognized → increase threshold (harder to merge).
  /// - If calculated < recognized → decrease threshold (easier to merge).
  void update({double? recognizedSum, required double calculatedSum}) {
    if (recognizedSum == null ||
        (recognizedSum - calculatedSum).abs() <=
            ReceiptConstants.sumTolerance) {
      _delta = 0;
      return;
    }
    if (calculatedSum > recognizedSum) {
      _delta = _clampInt(_delta + step, -maxDelta, maxDelta);
    } else {
      _delta = _clampInt(_delta - step, -maxDelta, maxDelta);
    }
  }

  /// Clamps [v] to the inclusive range [lo]..[hi] for integers.
  static int _clampInt(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
  }
}
