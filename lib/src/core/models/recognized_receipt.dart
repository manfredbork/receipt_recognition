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

  /// The label text (e.g., "Total" or "Summe") associated with the recognized sum.
  RecognizedSumLabel? sumLabel;

  /// The company/store name recognized from the receipt, if any.
  RecognizedCompany? company;

  /// The bounding box of the receipt including skew angle and skew bounding box.
  RecognizedBoundingBox? boundingBox;

  /// All intermediate OCR entities parsed from the receipt (lines, labels, amounts, etc.).
  final List<RecognizedEntity>? entities;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sum,
    this.sumLabel,
    this.company,
    this.entities,
    this.boundingBox,
  });

  /// Creates an empty receipt with the current timestamp.
  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now(), entities: []);

  /// Creates a [RecognizedReceipt] from a JSON map for testing or deserialization.
  factory RecognizedReceipt.fromJson(Map<String, dynamic> json) {
    return RecognizedReceipt(
      positions:
          (json['positions'] as List)
              .map((p) => RecognizedPosition.fromJson(p))
              .toList(),
      sum:
          json['sum'] != null
              ? RecognizedSum(
                value: (json['sum']['value'] as num),
                line: DummyTextLine(),
              )
              : null,
      timestamp: DateTime.now(),
      entities: [],
    );
  }

  /// Creates a copy of this receipt with optionally updated properties.
  RecognizedReceipt copyWith({
    RecognizedCompany? company,
    RecognizedSum? sum,
    RecognizedSumLabel? sumLabel,
    RecognizedBoundingBox? boundingBox,
    List<RecognizedEntity>? entities,
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
  }) {
    return RecognizedReceipt(
      company: company ?? this.company,
      sum: sum ?? this.sum,
      sumLabel: sumLabel ?? this.sumLabel,
      boundingBox: boundingBox ?? this.boundingBox,
      entities: entities ?? this.entities,
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// A simple fingerprint based on position values and sum.
  String get fingerprint {
    final positionsHash = positions
        .map((p) => '${p.product.formattedValue}:${p.price.value}')
        .join(',');
    final sumValue = sum?.formattedValue ?? '';
    return '$positionsHash|$sumValue';
  }

  /// Calculates the sum of all position prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  /// Whether the receipt has a valid match between calculated and recognized sum.
  bool get isValid =>
      calculatedSum.formattedValue == sum?.formattedValue &&
      calculatedSum.value > 0.0;
}
