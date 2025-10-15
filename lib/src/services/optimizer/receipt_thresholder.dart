import 'package:receipt_recognition/src/utils/configuration/index.dart';

/// Dynamically adjusts confidence thresholds for position grouping based on sum feedback.
final class ReceiptThresholder {
  /// Baseline confidence threshold (0–100).
  final int baseThreshold;

  /// Maximum allowed deviation from the baseline.
  final int maxDelta;

  /// Step size for each threshold adjustment.
  final int step;

  /// Current dynamic offset applied to [baseThreshold].
  int _delta = 0;

  /// Creates a new adaptive thresholder; defaults baseline to runtime setting.
  ReceiptThresholder({int? baseThreshold, this.maxDelta = 20, this.step = 5})
    : baseThreshold =
          baseThreshold ?? ReceiptRuntime.tuning.optimizerConfidenceThreshold,
      assert((baseThreshold ?? 0) >= 0 && (baseThreshold ?? 0) <= 100),
      assert(maxDelta >= 0),
      assert(step > 0);

  /// Builds a thresholder from the current runtime configuration.
  factory ReceiptThresholder.fromRuntime() => ReceiptThresholder(
    baseThreshold: ReceiptRuntime.tuning.optimizerConfidenceThreshold,
  );

  /// Current threshold to use for grouping decisions (clamped to 0–100).
  int get threshold => _clampInt(baseThreshold + _delta, 0, 100);

  /// Resets the dynamic delta back to zero.
  void reset() => _delta = 0;

  /// Updates the threshold in response to recognized vs calculated sums.
  void update({double? recognizedSum, required double calculatedSum}) {
    final tol = ReceiptRuntime.tuning.sumTolerance;
    if (recognizedSum == null || (recognizedSum - calculatedSum).abs() <= tol) {
      _delta = 0;
      return;
    }
    if (calculatedSum > recognizedSum) {
      _delta = _clampInt(_delta + step, -maxDelta, maxDelta);
    } else {
      _delta = _clampInt(_delta - step, -maxDelta, maxDelta);
    }
  }

  /// Clamps an integer to the inclusive range [lo]..[hi].
  static int _clampInt(int v, int lo, int hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
  }
}
