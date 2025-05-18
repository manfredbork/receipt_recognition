import 'package:receipt_recognition/receipt_recognition.dart';

final class ScanProgress {
  final List<RecognizedPosition> addedPositions;
  final List<RecognizedPosition> updatedPositions;
  final int? estimatedPercentage;

  ScanProgress({
    required this.addedPositions,
    required this.updatedPositions,
    this.estimatedPercentage,
  });
}
