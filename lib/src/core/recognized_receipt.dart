import 'receipt_models.dart';
import 'recognized_position.dart';

class RecognizedReceipt {
  List<RecognizedPosition> positions;
  DateTime timestamp;
  RecognizedSumLabel? sumLabel;
  RecognizedSum? sum;
  RecognizedCompany? company;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.sumLabel,
    this.sum,
    this.company,
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
  }) {
    return RecognizedReceipt(
      positions: positions ?? this.positions,
      timestamp: timestamp ?? this.timestamp,
      sumLabel: sumLabel ?? this.sumLabel,
      sum: sum ?? this.sum,
      company: company ?? this.company,
    );
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;
}
