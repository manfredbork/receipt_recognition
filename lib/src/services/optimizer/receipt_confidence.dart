part of 'receipt_optimizer.dart';

/// Result of evaluating how well a position fits a group.
final class _ConfidenceResult {
  /// Product-side confidence computed by the group.
  final Confidence productConfidence;

  /// Price-side confidence computed by the group.
  final Confidence priceConfidence;

  /// Combined confidence used for the selection decision (0–100).
  final int confidence;

  /// Whether the position should be assigned to the group.
  final bool shouldUseGroup;

  const _ConfidenceResult({
    required this.productConfidence,
    required this.priceConfidence,
    required this.confidence,
    required this.shouldUseGroup,
  });

  @override
  String toString() =>
      '_ConfidenceResult(prod:${productConfidence.value}, '
      'price:${priceConfidence.value}, conf:$confidence, use:$shouldUseGroup)';
}
