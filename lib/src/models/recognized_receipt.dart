import 'dart:ui';

import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

/// Complete recognized receipt (positions, totals, store, date, bounds, entities).
class RecognizedReceipt {
  /// Line items.
  List<RecognizedPosition> positions;

  /// Processing timestamp.
  DateTime timestamp;

  /// Recognized total (if any).
  RecognizedTotal? total;

  /// Label associated with the recognized total (e.g. "Total").
  RecognizedTotalLabel? totalLabel;

  /// Recognized store (if any).
  RecognizedStore? store;

  /// Recognized purchase date (if any).
  RecognizedPurchaseDate? purchaseDate;

  /// Receipt bounds including skew.
  RecognizedBounds? bounds;

  /// Parsed OCR entities.
  final List<RecognizedEntity>? entities;

  /// Creates a recognized receipt.
  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.total,
    this.totalLabel,
    this.store,
    this.purchaseDate,
    this.bounds,
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

    final rawTotal = json['total'];
    RecognizedTotal? total;
    if (rawTotal is Map<String, dynamic>) {
      final v = rawTotal['value'];
      final numValue = v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
      total = RecognizedTotal(value: numValue, line: ReceiptTextLine());
    }

    final rawPd = json['purchase_date'];
    RecognizedPurchaseDate? purchaseDate;
    if (rawPd != null) {
      purchaseDate = RecognizedPurchaseDate(
        value: ReceiptFormatter.parseNumericYMD(rawPd) ?? DateTime.now(),
        line: ReceiptTextLine(),
      );
    }

    final ts =
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now();

    return RecognizedReceipt(
      positions: positions,
      total: total,
      purchaseDate: purchaseDate,
      timestamp: ts,
      entities: [],
    );
  }

  /// Returns a copy with updated fields.
  RecognizedReceipt copyWith({
    RecognizedStore? store,
    RecognizedTotal? total,
    RecognizedTotalLabel? totalLabel,
    RecognizedPurchaseDate? purchaseDate,
    RecognizedBounds? bounds,
    List<RecognizedEntity>? entities,
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
  }) {
    return RecognizedReceipt(
      store: store ?? this.store,
      total: total ?? this.total,
      totalLabel: totalLabel ?? this.totalLabel,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      bounds: bounds ?? this.bounds,
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

  /// Legacy accessor for [sum] maintained for backward compatibility.
  @Deprecated(
    'Use `total` instead. This getter will be removed in a future release.',
  )
  RecognizedSum? get sum =>
      total != null
          ? RecognizedSum(value: total!.value, line: total!.line)
          : null;

  /// Legacy accessor for [sumLabel] maintained for backward compatibility.
  @Deprecated(
    'Use `totalLabel` instead. This getter will be removed in a future release.',
  )
  RecognizedSumLabel? get sumLabel =>
      totalLabel != null
          ? RecognizedSumLabel(value: totalLabel!.value, line: totalLabel!.line)
          : null;

  /// Positions+total fingerprint.
  String get fingerprint {
    final positionsHash = positions
        .map((p) => '${p.product.formattedValue}:${p.price.value}')
        .join(',');
    final totalValue = total?.formattedValue ?? '';
    return '$positionsHash|$totalValue';
  }

  /// Total of all position prices.
  CalculatedTotal get calculatedTotal => CalculatedTotal(
    value: positions.fold<num>(0, (a, b) => a + b.price.value),
  );

  /// Legacy accessor for [calculatedSum] maintained for backward compatibility.
  @Deprecated(
    'Use `calculatedTotal` instead. This getter will be removed in a future release.',
  )
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: calculatedTotal.value);

  /// True if calculated and recognized totals match and value is positive.
  bool get isValid =>
      calculatedTotal.formattedValue == total?.formattedValue &&
      calculatedTotal.value > 0.0;

  /// True if the receipt has parsed entities.
  bool get isNotEmpty => !isEmpty;

  /// True if the receipt has no parsed entities.
  bool get isEmpty =>
      (entities == null || entities!.isEmpty) &&
      positions.isEmpty &&
      total == null &&
      store == null &&
      purchaseDate == null &&
      (bounds == null || bounds!.boundingBox == Rect.zero);

  /// True if a quorum of positions meet size, stability, and confidence gates.
  bool get isConfirmed {
    final t = ReceiptRuntime.tuning;
    final half = t.optimizerMaxCacheSize ~/ 2;
    final minSize = half < 4 ? 4 : (half > 8 ? 8 : half);
    final confThr = (t.optimizerConfidenceThreshold - 5).clamp(0, 100);
    final stabThr = t.optimizerStabilityThreshold;
    final passing =
        positions.where((p) {
          final enoughMembers = (p.group?.members.length ?? 0) >= minSize;
          final enoughStability = p.stability >= stabThr;
          final enoughConfidence = p.confidence >= confThr;
          return enoughMembers && enoughStability && enoughConfidence;
        }).length;

    final need =
        positions.length <= 3
            ? positions.length
            : (positions.length * 0.8).ceil();

    return passing >= need;
  }
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
  final int estimatedPercentage;

  /// Merged receipt built from all scans.
  final RecognizedReceipt mergedReceipt;

  /// Creates a scan progress snapshot.
  const RecognizedScanProgress({
    required this.positions,
    required this.addedPositions,
    required this.updatedPositions,
    required this.validationResult,
    required this.estimatedPercentage,
    required this.mergedReceipt,
  });

  /// Empty scan progress with empty receipt.
  factory RecognizedScanProgress.empty() => RecognizedScanProgress(
    positions: [],
    addedPositions: [],
    updatedPositions: [],
    validationResult: ReceiptValidationResult(
      status: ReceiptCompleteness.invalid,
      matchPercentage: 0,
      message: '',
    ),
    estimatedPercentage: 0,
    mergedReceipt: RecognizedReceipt.empty(),
  );
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

  /// Match percentage between calculated and declared total (0–100).
  final int matchPercentage;

  /// Human-readable validation message.
  final String message;

  /// Creates a validation result.
  const ReceiptValidationResult({
    required this.status,
    required this.matchPercentage,
    required this.message,
  });
}
