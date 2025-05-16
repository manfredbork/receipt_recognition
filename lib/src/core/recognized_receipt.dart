import 'receipt_models.dart';
import 'recognized_position.dart';

class RecognizedReceipt {
  List<RecognizedPosition> positions;
  DateTime timestamp;
  int minScans;
  bool? videoFeed;
  RecognizedSumLabel? sumLabel;
  RecognizedSum? sum;
  RecognizedCompany? company;

  RecognizedReceipt({
    required this.positions,
    required this.timestamp,
    this.videoFeed,
    this.sumLabel,
    this.sum,
    this.company,
  }) : minScans = videoFeed == true ? 3 : 1;

  factory RecognizedReceipt.empty() =>
      RecognizedReceipt(positions: [], timestamp: DateTime.now());

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

  RecognizedReceipt fromVideoFeed(bool videoFeed) {
    this.videoFeed = videoFeed;

    return this;
  }

  CalculatedSum get calculatedSum =>
      CalculatedSum(value: positions.fold(0.0, (a, b) => a + b.price.value));

  bool get isValid => calculatedSum.formattedValue == sum?.formattedValue;
}
