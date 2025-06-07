import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  group('ReceiptFormatter', () {
    setUp(() {
      Intl.defaultLocale = 'en_US';
    });

    group('format', () {
      test('should format integers with two decimal places', () {
        final values = [0, 1, 42, 100, -5];
        final expected = ['0.00', '1.00', '42.00', '100.00', '-5.00'];

        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });

      test('should format decimals with two decimal places', () {
        final values = [0.1, 1.5, 42.99, 100.999, -5.01];
        final expected = ['0.10', '1.50', '42.99', '101.00', '-5.01'];

        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });

      test('should handle very large and very small numbers', () {
        final values = [999999.99, 0.001, -0.005];
        final expected = ['999,999.99', '0.00', '-0.01'];

        for (int i = 0; i < values.length; i++) {
          expect(ReceiptFormatter.format(values[i]), expected[i]);
        }
      });
    });

    group('parse', () {
      test('should parse decimal strings to numbers', () {
        final strings = ['0.00', '1.00', '42.99', '100.00', '-5.01'];
        final expected = [0.0, 1.0, 42.99, 100.0, -5.01];

        for (int i = 0; i < strings.length; i++) {
          expect(ReceiptFormatter.parse(strings[i]), expected[i]);
        }
      });

      test('should parse formatted numbers with commas', () {
        final strings = ['1,000.00', '1,234.56', '999,999.99'];
        final expected = [1000.0, 1234.56, 999999.99];

        for (int i = 0; i < strings.length; i++) {
          expect(ReceiptFormatter.parse(strings[i]), expected[i]);
        }
      });

      test('should throw FormatException for invalid format', () {
        final invalidStrings = ['abc', '1.2.3', ''];

        for (final string in invalidStrings) {
          expect(() => ReceiptFormatter.parse(string), throwsFormatException);
        }
      });
    });

    group('trim', () {
      test('should remove spaces around decimal separators', () {
        final inputs = ['12 . 34', '56 , 78', '9.10', '11,12'];
        final expected = ['12.34', '56,78', '9.10', '11,12'];

        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptFormatter.trim(inputs[i]), expected[i]);
        }
      });

      test('should handle strings without decimal separators', () {
        final inputs = ['abc', '123', 'no separator here'];

        for (final input in inputs) {
          expect(ReceiptFormatter.trim(input), input);
        }
      });

      test('should handle complex cases with multiple separators', () {
        final inputs = [
          'Milk, Honey ,Butter',
          'cost: 56 , 78 EUR',
          '12 . 34 . 56',
        ];
        final expected = ['Milk,Honey,Butter', 'cost: 56,78 EUR', '12.34.56'];

        for (int i = 0; i < inputs.length; i++) {
          expect(ReceiptFormatter.trim(inputs[i]), expected[i]);
        }
      });
    });

    test('should work with different locales', () {
      final originalLocale = Intl.defaultLocale;

      try {
        Intl.defaultLocale = 'de_DE';
        expect(ReceiptFormatter.format(1234.56), '1.234,56');

        Intl.defaultLocale = 'en_US';
        expect(ReceiptFormatter.format(1234.56), '1,234.56');
      } finally {
        Intl.defaultLocale = originalLocale;
      }
    });
  });
}
