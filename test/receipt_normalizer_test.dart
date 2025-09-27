import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  group('ReceiptNormalizer', () {
    group('normalizeByAlternativeTexts', () {
      test('should return normalized text when given alternative texts', () {
        final alternativeTexts = [
          'Item!123',
          'ItemA123',
          'ItemB123',
          'ItemA123',
        ];

        final result = ReceiptNormalizer.normalizeByAlternativeTexts(
          alternativeTexts,
        );

        expect(result, 'ItemA');
      });

      test('should return null when no alternative texts are provided', () {
        final noAlternativeTexts = <String>[];

        final result = ReceiptNormalizer.normalizeByAlternativeTexts(
          noAlternativeTexts,
        );

        expect(result, null);
      });
    });

    group('normalizeTail', () {
      test('should remove price-like endings from text', () {
        final inputs = [
          'Tea 3.50 @',
          'Milk 2,50',
          'Bread 5,99 xyz',
          'Plain text',
        ];
        final expected = ['Tea', 'Milk', 'Bread', 'Plain text'];

        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptNormalizer.normalizeTail(inputs[i]), expected[i]);
        }
      });
    });

    group('normalizeSpecialSpaces', () {
      test('should merge tokens when needed', () {
        const bestText = 'Cof fee Beans';
        final otherTexts = ['Coffee Beans'];

        final result = ReceiptNormalizer.normalizeSpecialSpaces(
          bestText,
          otherTexts,
        );

        expect(result, 'Coffee Beans');
      });

      test('should not modify text when no merges are needed', () {
        const bestText = 'Coffee Beans';
        final otherTexts = ['Tea Bags'];

        final result = ReceiptNormalizer.normalizeSpecialSpaces(
          bestText,
          otherTexts,
        );

        expect(result, 'Coffee Beans');
      });

      test('should handle multiple merges in a single text', () {
        const bestText = 'Cof fee Be ans';
        final otherTexts = ['Cof fee Be ans', 'Cof fee Be ans', 'Coffee Beans'];

        final result = ReceiptNormalizer.normalizeSpecialSpaces(
          bestText,
          otherTexts,
        );

        expect(result, 'Coffee Beans');
      });
    });

    group('sortByFrequency', () {
      test('should sort strings by frequency in ascending order', () {
        final values = [
          'apple',
          'banana',
          'apple',
          'cherry',
          'banana',
          'apple',
        ];
        final expected = ['cherry', 'banana', 'apple'];

        final result = ReceiptNormalizer.sortByFrequency(values);

        expect(result, expected);
      });

      test('should return empty list when given empty list', () {
        final values = <String>[];

        final result = ReceiptNormalizer.sortByFrequency(values);

        expect(result, isEmpty);
      });

      test('should maintain order for equal frequencies', () {
        final values = ['apple', 'banana', 'cherry', 'date'];

        final result = ReceiptNormalizer.sortByFrequency(values);

        expect(result.length, 4);
        expect(result.contains('apple'), isTrue);
        expect(result.contains('banana'), isTrue);
        expect(result.contains('cherry'), isTrue);
        expect(result.contains('date'), isTrue);
      });
    });
  });
}
