/// Dynamically adjusts confidence thresholds for position grouping
/// based on receipt sum feedback (recognized vs calculated).
///
/// Helps balance under- and over-grouping in adaptive receipt scanning.
final class ReceiptThresholder {
  /// Baseline confidence threshold.
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
  });

  /// Current threshold to use for grouping decisions.
  int get threshold => (baseThreshold + _delta).clamp(0, 100);

  /// Resets the threshold back to the baseline.
  void reset() {
    _delta = 0;
  }

  /// Updates the threshold based on comparison of recognized and calculated sums.
  void update({double? recognizedSum, required double calculatedSum}) {
    if (recognizedSum == null ||
        (recognizedSum - calculatedSum).abs() <= 0.009) {
      _delta = 0;
      return;
    }

    if (calculatedSum > recognizedSum) {
      _delta = (_delta + step).clamp(-maxDelta, maxDelta);
    } else {
      _delta = (_delta - step).clamp(-maxDelta, maxDelta);
    }
  }
}
