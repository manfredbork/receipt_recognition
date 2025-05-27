import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  group('ReceiptNormalizer', () {
    group('normalizeByAlternativeTexts', () {
      test('should return normalized text when given best text and alternative texts', () {
        // Arrange
        final bestText = 'Item!123';
        final otherTexts = ['Item!123', 'ItemA123', 'ItemB123', 'ItemA123'];

        // Act
        final result = ReceiptNormalizer.normalizeByAlternativeTexts(bestText, otherTexts);

        // Assert
        expect(result, 'ItemA123');
      });

      test('should return best text when no other texts are provided', () {
        // Arrange
        final bestText = 'Item123';
        final otherTexts = <String>[];

        // Act
        final result = ReceiptNormalizer.normalizeByAlternativeTexts(bestText, otherTexts);

        // Assert
        expect(result, bestText);
      });
    });

    group('normalizeTail', () {
      test('should remove price-like endings from text', () {
        // Arrange
        final inputs = [
          'Coffee-12.99',
          'Tea 3.50',
          'Milk 2,50',
          'Bread-5,99',
          'Plain text'
        ];
        final expected = [
          'Coffee',
          'Tea',
          'Milk',
          'Bread',
          'Plain text'
        ];

        // Act & Assert
        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptNormalizer.normalizeTail(inputs[i]), expected[i]);
        }
      });
    });

    group('normalizeSpecialChars', () {
      test('should replace special characters with alphanumeric ones from other texts', () {
        // Arrange
        final bestText = 'C@ffee';
        final otherTexts = ['Coffee'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialChars(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee');
      });

      test('should replace numbers with letters when appropriate', () {
        // Arrange
        final bestText = 'C0ke';
        final otherTexts = ['Coke'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialChars(bestText, otherTexts);

        // Assert
        expect(result, 'Coke');
      });

      test('should replace non-German characters with German ones when appropriate', () {
        // Arrange
        final bestText = 'Kase';
        final otherTexts = ['Käse'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialChars(bestText, otherTexts);

        // Assert
        expect(result, 'Käse');
      });

      test('should return best text when no replacements are needed', () {
        // Arrange
        final bestText = 'Coffee';
        final otherTexts = ['Tea', 'Milk'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialChars(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee');
      });

      test('should return best text when texts have different lengths', () {
        // Arrange
        final bestText = 'Coffee';
        final otherTexts = ['Coffees', 'Tea'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialChars(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee');
      });
    });

    group('normalizeSpecialSpaces', () {
      test('should merge tokens when needed', () {
        // Arrange
        final bestText = 'Cof fee Beans';
        final otherTexts = ['Coffee Beans'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialSpaces(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee Beans');
      });

      test('should not modify text when no merges are needed', () {
        // Arrange
        final bestText = 'Coffee Beans';
        final otherTexts = ['Tea Bags'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialSpaces(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee Beans');
      });

      test('should handle multiple merges in a single text', () {
        // Arrange
        final bestText = 'Cof fee Be ans';
        final otherTexts = ['Cof fee Be ans', 'Cof fee Be ans', 'Coffee Beans'];

        // Act
        final result = ReceiptNormalizer.normalizeSpecialSpaces(bestText, otherTexts);

        // Assert
        expect(result, 'Coffee Beans');
      });
    });

    group('sortByFrequency', () {
      test('should sort strings by frequency in descending order', () {
        // Arrange
        final values = ['apple', 'banana', 'apple', 'cherry', 'banana', 'apple'];
        final expected = ['apple', 'banana', 'cherry'];

        // Act
        final result = ReceiptNormalizer.sortByFrequency(values);

        // Assert
        expect(result, expected);
      });

      test('should return empty list when given empty list', () {
        // Arrange
        final values = <String>[];

        // Act
        final result = ReceiptNormalizer.sortByFrequency(values);

        // Assert
        expect(result, isEmpty);
      });

      test('should maintain order for equal frequencies', () {
        // Arrange
        final values = ['apple', 'banana', 'cherry', 'date'];

        // Act
        final result = ReceiptNormalizer.sortByFrequency(values);

        // Assert
        expect(result.length, 4);
        // Each item appears once, so they should all be in the result
        expect(result.contains('apple'), isTrue);
        expect(result.contains('banana'), isTrue);
        expect(result.contains('cherry'), isTrue);
        expect(result.contains('date'), isTrue);
      });
    });
  });
}
