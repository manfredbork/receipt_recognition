import 'package:receipt_recognition/receipt_recognition.dart';

/// Complete recognized receipt (positions, totals, store, date, bounds, entities).
class RecognizedReceipt {
  /// Line items.
  List<RecognizedPosition> positions;

  /// Processing timestamp.
  DateTime timestamp;

  /// Recognized total sum (if any).
  RecognizedSum? sum;

  /// Label associated with the recognized sum (e.g. "Total").
  RecognizedSumLabel? sumLabel;

  /// Recognized store (if any).
  RecognizedStore? store;

  /// Recognized purchase date (if any).
  RecognizedPurchaseDate? purchaseDate;

  /// Receipt bounding box including skew.
  RecognizedBoundingBox? boundingBox;

  /// Parsed OCR entities.
  final List<RecognizedEntity>? entities;

  /// Creates a recognized receipt.
  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sum,
    this.sumLabel,
    this.store,
    this.purchaseDate,
    this.boundingBox,
    this.entities,
  });

  /// Empty receipt with current timestamp.
  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now(), entities: []);

  /// Creates a receipt from JSON.
  factory RecognizedReceipt.fromJson(Map<String, dynamic> json) {
    final rawPositions = (json['positions'] as List?) ?? const [];
    final positions =
        rawPositions
            .whereType<Map<String, dynamic>>()
            .map(RecognizedPosition.fromJson)
            .toList();

    final rawSum = json['sum'];
    RecognizedSum? sum;
    if (rawSum is Map<String, dynamic>) {
      final v = rawSum['value'];
      final numValue = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
      sum = RecognizedSum(value: numValue, line: DummyTextLine());
    }

    final rawPd = json['purchase_date'];
    RecognizedPurchaseDate? purchaseDate;
    if (rawPd != null) {
      purchaseDate = RecognizedPurchaseDate(
        value: rawPd.toString(),
        line: DummyTextLine(),
      );
    }

    final ts =
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now();

    return RecognizedReceipt(
      positions: positions,
      sum: sum,
      purchaseDate: purchaseDate,
      timestamp: ts,
      entities: [],
    );
  }

  /// Returns a copy with updated fields.
  RecognizedReceipt copyWith({
    RecognizedStore? store,
    RecognizedSum? sum,
    RecognizedSumLabel? sumLabel,
    RecognizedPurchaseDate? purchaseDate,
    RecognizedBoundingBox? boundingBox,
    List<RecognizedEntity>? entities,
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
  }) {
    return RecognizedReceipt(
      store: store ?? this.store,
      sum: sum ?? this.sum,
      sumLabel: sumLabel ?? this.sumLabel,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      boundingBox: boundingBox ?? this.boundingBox,
      entities: entities ?? this.entities,
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Legacy accessor for [store] maintained for backward compatibility.
  @Deprecated(
    'Use `store` instead. This getter will be removed in a future release.',
  )
  RecognizedCompany? get company =>
      store != null
          ? RecognizedCompany(value: store!.value, line: store!.line)
          : null;

  /// Positions+sum fingerprint.
  String get fingerprint {
    final positionsHash = positions
        .map((p) => '${p.product.formattedValue}:${p.price.value}')
        .join(',');
    final sumValue = sum?.formattedValue ?? '';
    return '$positionsHash|$sumValue';
  }

  /// Sum of all position prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold<num>(0, (a, b) => a + b.price.value));

  /// True if calculated and recognized sums match and value is positive.
  bool get isValid =>
      calculatedSum.formattedValue == sum?.formattedValue &&
      calculatedSum.value > 0.0;
}

/// Progress snapshot of an ongoing receipt scan.
///
/// Includes recognized positions, validation state, and the merged receipt.
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

  /// Merged receipt built from all scans.
  final RecognizedReceipt? mergedReceipt;

  /// Creates a scan progress snapshot.
  const RecognizedScanProgress({
    required this.positions,
    required this.addedPositions,
    required this.updatedPositions,
    required this.validationResult,
    this.estimatedPercentage,
    this.mergedReceipt,
  });
}

/// Completeness level of a recognized receipt.
enum ReceiptCompleteness {
  /// Fully complete with perfect validation.
  complete,

  /// Nearly complete with high validation score.
  nearlyComplete,

  /// Partially recognized but incomplete.
  incomplete,

  /// Missing critical information or invalid.
  invalid,
}

/// Validation result for a recognized receipt.
class ReceiptValidationResult {
  /// Completeness status.
  final ReceiptCompleteness status;

  /// Match percentage between calculated and declared sum (0–100).
  final int? matchPercentage;

  /// Human-readable validation message.
  final String? message;

  /// Creates a validation result.
  const ReceiptValidationResult({
    required this.status,
    this.matchPercentage,
    this.message,
  });
}
