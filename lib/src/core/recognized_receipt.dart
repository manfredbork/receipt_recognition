import 'receipt_models.dart';
import 'recognized_position.dart';

class RecognizedReceipt {
  List<RecognizedPosition> positions;
  DateTime timestamp;
  RecognizedSumLabel? sumLabel;
  RecognizedSum? sum;
  RecognizedCompany? company;
  bool scanComplete;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sumLabel,
    this.sum,
    this.company,
    this.scanComplete = true,
  });

  factory RecognizedReceipt.empty() {
    return RecognizedReceipt(positions: [], timestamp: DateTime.now());
  }

  RecognizedReceipt copyWith({
    List<RecognizedPosition>? positions,
    DateTime? timestamp,
    RecognizedSumLabel? sumLabel,
    RecognizedSum? sum,
    RecognizedCompany? company,
    bool? scanComplete,
  }) {
    return RecognizedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
      scanComplete: scanComplete ?? this.scanComplete,
    );
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  bool get isCorrectSum => calculatedSum.formattedValue == sum?.formattedValue;

  bool get isScanComplete => scanComplete;

  bool get isValid => isCorrectSum && isScanComplete;
}

final class Progress {
  final List<RecognizedPosition> addedPositions;
  final List<RecognizedPosition> updatedPositions;
  final int? estimatedPercentage;

  Progress({
    required this.addedPositions,
    required this.updatedPositions,
    this.estimatedPercentage,
  });
}
