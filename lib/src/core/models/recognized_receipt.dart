import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a complete recognized receipt with all its components.
///
/// Contains positions (line items), total sum, company name, and validation methods.
class RecognizedReceipt {
  /// Line items recognized from the receipt.
  List<RecognizedPosition> positions;

  /// When this receipt was processed.
  DateTime timestamp;

  /// The total sum recognized from the receipt, if any.
  RecognizedSum? sum;

  /// The company/store name recognized from the receipt, if any.
  RecognizedCompany? company;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sum,
    this.company,
  });

  /// Creates an empty receipt with the current timestamp.
  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now());

  /// Creates a copy of this receipt with optionally updated properties.
  RecognizedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    RecognizedSum? sum,
    RecognizedCompany? company,
  }) {
    return RecognizedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      sum: sum ?? this.sum,
      company: company ?? this.company,
    );
  }

  /// Calculates the sum of all position prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  /// Whether the receipt has a valid match between calculated and recognized sum.
  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;
}

/// Represents the progress of an ongoing receipt scan process.
///
/// Contains information about newly recognized items and current validation status.
final class ScanProgress {
  /// Positions that were newly added in this scan.
  final List<RecognizedPosition> addedPositions;

  /// Positions that were updated in this scan.
  final List<RecognizedPosition> updatedPositions;

  /// Current validation result for the receipt.
  final ValidationResult validationResult;

  /// Estimated percentage of completion (0-100).
  final int? estimatedPercentage;

  /// The current merged receipt from all scans, if available.
  final RecognizedReceipt? mergedReceipt;

  ScanProgress({
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
class ValidationResult {
  /// The completeness status of the receipt.
  final ReceiptCompleteness status;

  /// Percentage match between calculated and declared sum (0-100).
  final int? matchPercentage;

  /// Human-readable validation message.
  final String? message;

  ValidationResult({required this.status, this.matchPercentage, this.message});
}
