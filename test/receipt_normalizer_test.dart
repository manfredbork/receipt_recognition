import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

PositionGroup groupFrom(List<String> values) {
  final positions =
      values.map((v) {
        return RecognizedPosition(
          product: RecognizedProduct(value: v, line: dummyTextLine),
          price: RecognizedPrice(value: 1.0, line: dummyTextLine),
          timestamp: DateTime.now(),
          group: PositionGroup.empty(),
          operation: Operation.added,
          positionIndex: 0,
        );
      }).toList();
  return PositionGroup(positions: positions);
}

final dummyTextLine = TextLine(
  text: '',
  recognizedLanguages: [],
  boundingBox: const Rect.fromLTWH(0, 0, 0, 0),
  cornerPoints: [],
  elements: [],
  confidence: null,
  angle: null,
);

void main() {
  group('ReceiptNormalizer._normalizeFromGroup', () {
    test('returns the longest frequent name from group', () {
      final group = groupFrom([
        'Chicken',
        'Chicken Nuggets',
        'Chicken Nuggets 6er',
        'Chicken Nuggets 6er',
      ]);
      final result = ReceiptNormalizer.normalizeFromGroup(group);
      expect(result, 'Chicken Nuggets 6er');
    });

    test('keeps proper internal spaces', () {
      final group = groupFrom(['Co ke Zero', 'Coke Zero', 'Coke Zero']);
      final result = ReceiptNormalizer.normalizeFromGroup(group);
      expect(result, 'Coke Zero');
    });

    test('removes trailing OCR garbage', () {
      final group = groupFrom(['Apples', 'Apples +#*', 'Apples']);
      final result = ReceiptNormalizer.normalizeFromGroup(group);
      expect(result, 'Apples');
    });
  });
}
