import 'dart:ui';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:test/test.dart';

void main() {
  test('resolveOrder reconstructs correct sequence from fragmented scans', () {
    final now = DateTime.now();

    RecognizedPosition createPosition(String name, double price, int offset, int index) {
      final timestamp = now.add(Duration(milliseconds: offset));
      final dummyLine = TextLine(
        text: name,
        recognizedLanguages: [],
        boundingBox: const Rect.fromLTWH(0, 0, 0, 0),
        cornerPoints: [],
        elements: [],
        confidence: null,
        angle: null,
      );

      final product = RecognizedProduct(line: dummyLine, value: name);
      final priceObj = RecognizedPrice(line: dummyLine, value: price);

      return RecognizedPosition(
        product: product,
        price: priceObj,
        timestamp: timestamp,
        group: PositionGroup.empty(),
        operation: Operation.added,
        positionIndex: index,
      );
    }

    final milk = createPosition('Milk', 1.29, 0, 0);
    final chocolate = createPosition('Chocolate', 0.89, 10, 0);
    final butter = createPosition('Butter', 2.20, 20, 0);
    final oranges = createPosition('Oranges', 3.00, 25, 0);
    final apples = createPosition('Apples', 2.50, 30, 0);
    final coke = createPosition('Coke Zero', 1.00, 35, 0);

    final groups = [
      PositionGroup.fromPosition(milk),
      PositionGroup.fromPosition(chocolate),
      PositionGroup.fromPosition(butter),
      PositionGroup.fromPosition(oranges),
      PositionGroup.fromPosition(apples),
      PositionGroup.fromPosition(coke),
    ];

    final graph = PositionGraph(groups);
    final result = graph.resolveOrder();

    final orderedNames = result.map((p) => p.product.value).toList();

    expect(orderedNames, [
      'Milk',
      'Chocolate',
      'Butter',
      'Oranges',
      'Apples',
      'Coke Zero',
    ]);
  });
}
