part of 'receipt_optimizer.dart';

/// Private helpers for selecting and validating stable sum candidates.
extension _ReceiptSumSelectionExt on ReceiptOptimizer {
  /// Picks the best confirmed sum candidate for [receipt] by minimal vertical distance.
  ///
  /// Only candidates with confirmations ≥ [_sumConfirmationThreshold] and that pass
  /// [_isConfirmedSumValid] are considered.
  _SumCandidate? _pickStableSum(RecognizedReceipt receipt) => minBy(
    _sumCandidates.where(
      (c) =>
          c.confirmations >= _sumConfirmationThreshold &&
          _isConfirmedSumValid(c, receipt),
    ),
    (c) => c.verticalDistance,
  );

  /// Returns whether a confirmed sum candidate is plausible for [receipt].
  ///
  /// Requires at least two positions and the absolute difference between the candidate
  /// sum and the calculated sum to be within [ReceiptConstants.sumTolerance].
  bool _isConfirmedSumValid(
    _SumCandidate candidate,
    RecognizedReceipt receipt,
  ) {
    if (receipt.positions.length < 2) return false;
    final calculated = receipt.calculatedSum.value;
    return (candidate.sum.value - calculated).abs() <=
        ReceiptConstants.sumTolerance;
  }
}

/// Candidate pair of (sum label, numeric sum) observed near each other.
final class _SumCandidate {
  /// The textual label (e.g., "Total", "Summe") that points to the sum value.
  final RecognizedSumLabel label;

  /// The numeric sum value found near [label].
  final RecognizedSum sum;

  /// Vertical distance (in px) between [label] and [sum] after skew correction.
  final int verticalDistance;

  /// Confirmation counter used to identify stable candidates.
  int confirmations = 1;

  _SumCandidate({
    required this.label,
    required this.sum,
    required this.verticalDistance,
  });

  /// Equivalence under OCR noise: same label text (case/space-normalized)
  /// and sum values within [ReceiptConstants.sumTolerance].
  bool matches(_SumCandidate other) {
    String norm(String s) =>
        s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    final sameLabel = norm(label.line.text) == norm(other.label.line.text);
    final closeSum =
        (sum.value - other.sum.value).abs() <= ReceiptConstants.sumTolerance;
    return sameLabel && closeSum;
  }

  /// Increments the confirmation counter.
  void confirm() => confirmations++;
}
