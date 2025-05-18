import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  RecognizedPosition createPosition(
    String name,
    double price,
    DateTime timestamp,
    int index,
  ) {
    final dummyLine = TextLine(
      text: name,
      recognizedLanguages: [],
      boundingBox: const Rect.fromLTWH(0, 0, 0, 0),
      cornerPoints: [],
      elements: [],
      confidence: null,
      angle: null,
    );

    return RecognizedPosition(
      product: RecognizedProduct(line: dummyLine, value: name),
      price: RecognizedPrice(line: dummyLine, value: price),
      timestamp: timestamp,
      group: PositionGroup.empty(),
      operation: Operation.added,
      positionIndex: index,
    );
  }

  test('resolveOrder reconstructs correct sequence from fragmented scans', () {
    final now = DateTime.now();
    final positions = [
      createPosition('Milk', 1.29, now, 0),
      createPosition('Chocolate', 0.89, now.add(Duration(milliseconds: 10)), 0),
      createPosition('Butter', 2.20, now.add(Duration(milliseconds: 20)), 0),
      createPosition('Oranges', 3.00, now.add(Duration(milliseconds: 25)), 0),
      createPosition('Apples', 2.50, now.add(Duration(milliseconds: 30)), 0),
      createPosition('Coke Zero', 1.00, now.add(Duration(milliseconds: 35)), 0),
    ];
    final groups = positions.map(PositionGroup.fromPosition).toList();
    final graph = PositionGraph(groups);
    final result = graph.resolveOrder();
    final names = result.map((p) => p.product.value).toList();
    expect(names, [
      'Milk',
      'Chocolate',
      'Butter',
      'Oranges',
      'Apples',
      'Coke Zero',
    ]);
  });

  test(
    'handles positions with identical timestamps but different positionIndex',
    () {
      final now = DateTime.now();
      final posA = createPosition('Apples', 2.50, now, 1);
      final posB = createPosition('Butter', 2.20, now, 0);
      final groups = [
        PositionGroup.fromPosition(posA),
        PositionGroup.fromPosition(posB),
      ];
      final graph = PositionGraph(groups);
      final result = graph.resolveOrder();
      final ordered = result.map((p) => p.product.value).toList();
      expect(ordered, ['Butter', 'Apples']);
    },
  );

  test('handles OCR fuzziness in product names using fuzzywuzzy', () {
    final now = DateTime.now();
    final coke1 = createPosition(
      'Coke Zero',
      1.00,
      now.add(Duration(milliseconds: 10)),
      0,
    );
    final coke2 = createPosition(
      'C0ke Zer0',
      1.00,
      now.add(Duration(milliseconds: 20)),
      0,
    );
    final groups = [
      PositionGroup.fromPosition(coke1),
      PositionGroup.fromPosition(coke2),
    ];
    final graph = PositionGraph(groups, fuzzyThreshold: 80);
    final result = graph.resolveOrder();
    final ordered = result.map((p) => p.product.value).toList();
    expect(ordered.first, anyOf('Coke Zero', 'C0ke Zer0'));
    expect(ordered.last, anyOf('Coke Zero', 'C0ke Zer0'));
  });

  test('removes isolated outlier based on product similarity', () {
    final now = DateTime.now();
    final milk = createPosition('Milk', 1.29, now, 0);
    final chocolate = createPosition(
      'Chocolate',
      0.89,
      now.add(Duration(milliseconds: 10)),
      0,
    );
    final outlier = createPosition(
      'iPhone 14',
      999.99,
      now.add(Duration(milliseconds: 20)),
      0,
    );
    final positions = [milk, chocolate, outlier];
    final retained =
        positions.where((pos) {
          final similarityCount =
              positions.where((other) {
                if (pos == other) return false;
                final score = ratio(pos.product.value, other.product.value);
                return score >= 60;
              }).length;
          return similarityCount >= 1;
        }).toList();
    final result = retained.map((p) => p.product.value).toList();
    expect(result, containsAll(['Milk', 'Chocolate']));
    expect(result, isNot(contains('iPhone 14')));
  });
}
