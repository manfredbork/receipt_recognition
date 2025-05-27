import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  group('ReceiptFormatter', () {
    setUp(() {
      // Set a specific locale for consistent testing
      Intl.defaultLocale = 'en_US';
    });

    group('format', () {
      test('should format integers with two decimal places', () {
        // Arrange
        final values = [0, 1, 42, 100, -5];
        final expected = ['0.00', '1.00', '42.00', '100.00', '-5.00'];

        // Act & Assert
        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });

      test('should format decimals with two decimal places', () {
        // Arrange
        final values = [0.1, 1.5, 42.99, 100.999, -5.01];
        final expected = ['0.10', '1.50', '42.99', '101.00', '-5.01'];

        // Act & Assert
        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });

      test('should handle very large and very small numbers', () {
        // Arrange
        final values = [999999.99, 0.001, -0.005];
        final expected = ['999,999.99', '0.00', '-0.01'];

        // Act & Assert
        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });
    });

    group('parse', () {
      test('should parse decimal strings to numbers', () {
        // Arrange
        final strings = ['0.00', '1.00', '42.99', '100.00', '-5.01'];
        final expected = [0.0, 1.0, 42.99, 100.0, -5.01];

        // Act & Assert
        for (int i = 0; i < strings.length; i++) {
          expect(ReceiptFormatter.parse(strings[i]), expected[i]);
        }
      });

      test('should parse formatted numbers with commas', () {
        // Arrange
        final strings = ['1,000.00', '1,234.56', '999,999.99'];
        final expected = [1000.0, 1234.56, 999999.99];

        // Act & Assert
        for (int i = 0; i < strings.length; i++) {
          expect(ReceiptFormatter.parse(strings[i]), expected[i]);
        }
      });

      test('should throw FormatException for invalid format', () {
        // Arrange
        final invalidStrings = ['abc', '1.2.3', ''];

        // Act & Assert
        for (final string in invalidStrings) {
          expect(() => ReceiptFormatter.parse(string), throwsFormatException);
        }
      });
    });

    group('trim', () {
      test('should remove spaces around decimal separators', () {
        // Arrange
        final inputs = ['12 . 34', '56 , 78', '9.10', '11,12'];
        final expected = ['12.34', '56,78', '9.10', '11,12'];

        // Act & Assert
        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptFormatter.trim(inputs[i]), expected[i]);
        }
      });

      test('should handle strings without decimal separators', () {
        // Arrange
        final inputs = ['abc', '123', 'no separator here'];

        // Act & Assert
        for (final input in inputs) {
          expect(ReceiptFormatter.trim(input), input);
        }
      });

      test('should handle complex cases with multiple separators', () {
        // Arrange
        final inputs = ['Milk, Honey ,Butter', 'cost: 56 , 78 EUR', '12 . 34 . 56'];
        final expected = ['Milk,Honey,Butter', 'cost: 56,78 EUR', '12.34.56'];

        // Act & Assert
        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptFormatter.trim(inputs[i]), expected[i]);
        }
      });
    });

    test('should work with different locales', () {
      // Save original locale
      final originalLocale = Intl.defaultLocale;

      try {
        // Test with European locale
        Intl.defaultLocale = 'de_DE';
        expect(ReceiptFormatter.format(1234.56), '1.234,56');

        // Test with US locale
        Intl.defaultLocale = 'en_US';
        expect(ReceiptFormatter.format(1234.56), '1,234.56');
      } finally {
        // Restore original locale
        Intl.defaultLocale = originalLocale;
      }
    });
  });
}
