import 'package:receipt_recognition/receipt_recognition.dart';

/// Represents a complete recognized receipt with all its components.
///
/// Contains positions (line items), total sum, company name,
/// bounding box, and parsed OCR entities.
class RecognizedReceipt {
  /// Line items recognized from the receipt.
  List<RecognizedPosition> positions;

  /// Timestamp when this receipt was processed.
  DateTime timestamp;

  /// The recognized total sum, if any.
  RecognizedSum? sum;

  /// The label associated with the recognized sum (e.g. "Total").
  RecognizedSumLabel? sumLabel;

  /// The recognized company/store name, if any.
  RecognizedCompany? company;

  /// The bounding box of the receipt including skew.
  RecognizedBoundingBox? boundingBox;

  /// All intermediate OCR entities parsed from the receipt.
  final List<RecognizedEntity>? entities;

  /// Creates a new recognized receipt.
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

  /// Creates a receipt from a JSON map.
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

  /// Creates a copy with optionally updated properties.
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

  /// A simple fingerprint string based on positions and sum.
  String get fingerprint {
    final positionsHash = positions
        .map((p) => '${p.product.formattedValue}:${p.price.value}')
        .join(',');
    final sumValue = sum?.formattedValue ?? '';
    return '$positionsHash|$sumValue';
  }

  /// The calculated sum of all position prices.
  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  /// True if the calculated and recognized sum match and value is positive.
  bool get isValid =>
      calculatedSum.formattedValue == sum?.formattedValue &&
      calculatedSum.value > 0.0;
}
