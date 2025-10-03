import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents the progress of an ongoing receipt scan process.
///
/// Contains information about newly recognized items and current validation status.
final class RecognizedScanProgress {
  /// Positions that were recognized in this scan.
  final List<RecognizedPosition> positions;

  /// Positions that were newly added in this scan.
  final List<RecognizedPosition> addedPositions;

  /// Positions that were updated in this scan.
  final List<RecognizedPosition> updatedPositions;

  /// Current validation result for the receipt.
  final ReceiptValidationResult validationResult;

  /// Estimated percentage of completion (0-100).
  final int? estimatedPercentage;

  /// The current merged receipt from all scans, if available.
  final RecognizedReceipt? mergedReceipt;

  RecognizedScanProgress({
    required this.positions,
    required this.addedPositions,
    required this.updatedPositions,
    required this.validationResult,
    this.estimatedPercentage,
    this.mergedReceipt,
  });
}

/// Indicates the completeness level of a recognized receipt.
enum ReceiptCompleteness {
  /// Receipt is complete with perfect validation.
  complete,

  /// Receipt is nearly complete with high validation score.
  nearlyComplete,

  /// Receipt is partially recognized but incomplete.
  incomplete,

  /// Receipt lacks critical information and is invalid.
  invalid,
}

/// Contains validation results for a recognized receipt.
class ReceiptValidationResult {
  /// The completeness status of the receipt.
  final ReceiptCompleteness status;

  /// Percentage match between calculated and declared sum (0-100).
  final int? matchPercentage;

  /// Human-readable validation message.
  final String? message;

  ReceiptValidationResult({
    required this.status,
    this.matchPercentage,
    this.message,
  });
}
