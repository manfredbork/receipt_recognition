import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents the progress of an ongoing receipt scan process.
///
/// Contains recognized positions, validation status, and the merged receipt.
final class RecognizedScanProgress {
  /// All positions recognized in this scan.
  final List<RecognizedPosition> positions;

  /// Positions newly added in this scan.
  final List<RecognizedPosition> addedPositions;

  /// Positions updated in this scan.
  final List<RecognizedPosition> updatedPositions;

  /// Current validation result of the receipt.
  final ReceiptValidationResult validationResult;

  /// Estimated completion percentage (0–100).
  final int? estimatedPercentage;

  /// The current merged receipt from all scans.
  final RecognizedReceipt? mergedReceipt;

  /// Creates a new scan progress snapshot.
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
  /// Receipt is fully complete with perfect validation.
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
  /// Completeness status of the receipt.
  final ReceiptCompleteness status;

  /// Match percentage between calculated and declared sum (0–100).
  final int? matchPercentage;

  /// Human-readable validation message.
  final String? message;

  /// Creates a new validation result.
  ReceiptValidationResult({
    required this.status,
    this.matchPercentage,
    this.message,
  });
}
