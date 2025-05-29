import 'package:receipt_recognition/receipt_recognition.dart';

class RecognizedReceipt {
  List<RecognizedPosition> positions;
  DateTime timestamp;
  RecognizedSum? sum;
  RecognizedCompany? company;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sum,
    this.company,
  });

  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now());

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

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;
}

final class ScanProgress {
  final List<RecognizedPosition> addedPositions;
  final List<RecognizedPosition> updatedPositions;
  final ValidationResult validationResult;
  final int? estimatedPercentage;
  final RecognizedReceipt? mergedReceipt;

  ScanProgress({
    required this.addedPositions,
    required this.updatedPositions,
    required this.validationResult,
    this.estimatedPercentage,
    this.mergedReceipt,
  });
}

enum ReceiptCompleteness { complete, nearlyComplete, incomplete, invalid }

class ValidationResult {
  final ReceiptCompleteness status;
  final int? matchPercentage;
  final String? message;

  ValidationResult({required this.status, this.matchPercentage, this.message});
}
