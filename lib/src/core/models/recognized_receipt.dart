import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a fully or partially recognized receipt from OCR analysis.
///
/// Includes a list of scanned line items, optional metadata such as total sum,
/// company name, and whether the data comes from a live video feed.
class RecognizedReceipt {
  /// All recognized product/price positions on the receipt.
  List<RecognizedPosition> positions;

  /// The time at which this scan was captured.
  DateTime timestamp;

  /// Minimum number of observations required to consider a group valid.
  ///
  /// This is typically higher when using video feeds (e.g., 5) and lower (1) otherwise.
  int minScans;

  /// Whether the scan came from a live camera feed.
  bool? videoFeed;

  /// The label associated with the total sum (e.g. "TOTAL", "SUMME").
  RecognizedSumLabel? sumLabel;

  /// The total sum recognized from the receipt.
  RecognizedSum? sum;

  /// The recognized store or company name.
  RecognizedCompany? company;

  /// Creates a [RecognizedReceipt] instance with optional metadata.
  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.videoFeed,
    this.sumLabel,
    this.sum,
    this.company,
  }) : minScans = videoFeed == true ? 5 : 1;

  /// Returns an empty receipt with current timestamp and no data.
  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now());

  /// Returns a new instance with optionally updated fields.
  RecognizedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    bool? videoFeed,
    RecognizedSumLabel? sumLabel,
    RecognizedSum? sum,
    RecognizedCompany? company,
  }) {
    return RecognizedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      videoFeed: videoFeed ?? this.videoFeed,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
    );
  }

  /// Marks this receipt as coming from a video feed and updates [minScans] accordingly.
  RecognizedReceipt fromVideoFeed(bool videoFeed) {
    this.videoFeed = videoFeed;
    return this;
  }

  /// Returns the sum of all recognized line item prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  /// Returns `true` if the calculated and recognized sums match.
  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;
}

/// Represents the state of a multi-frame scanning process.
///
/// Used to track which positions have been added or updated, and an optional
/// progress estimate.
final class ScanProgress {
  /// New positions that have been added during scanning.
  final List<RecognizedPosition> addedPositions;

  /// Existing positions that were refined or updated.
  final List<RecognizedPosition> updatedPositions;

  /// Optional estimate of how close the scan is to completion (0–100).
  final int? estimatedPercentage;

  /// Creates a [ScanProgress] instance to describe recognition state.
  ScanProgress({
    required this.addedPositions,
    required this.updatedPositions,
    this.estimatedPercentage,
  });
}
