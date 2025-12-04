import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

ReceiptOptions makeOptionsFromLists({List<String> groups = const []}) {
  return ReceiptOptions(
    override: <String, dynamic>{'allowedProductGroups': groups},
  );
}

void main() {
  group('ReceiptNormalizer', () {
    group('normalizeToProductGroup', () {
      setUp(() {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: const []));
      });

      test('strips disallowed characters and returns cleaned value', () {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: const []));
        final r = ReceiptNormalizer.normalizeToProductGroup(
          '  Elec-tronics 123! ',
        );
        expect(r, equals('Electronics123'));
      });

      test('returns empty string when cleaned value is empty', () {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: const []));
        final r = ReceiptNormalizer.normalizeToProductGroup('---///***');
        expect(r, equals(''));
      });

      test('enforces allowlist when non-empty (exact cleaned match)', () {
        ReceiptRuntime.setOptions(
          makeOptionsFromLists(groups: ['BAKERY', 'dairy']),
        );

        expect(
          ReceiptNormalizer.normalizeToProductGroup('BAKERY'),
          equals('BAKERY'),
        );
        expect(
          ReceiptNormalizer.normalizeToProductGroup('dairy'),
          equals('dairy'),
        );
        expect(ReceiptNormalizer.normalizeToProductGroup('Dairy'), equals(''));
        expect(
          ReceiptNormalizer.normalizeToProductGroup('Electronics!'),
          equals(''),
        );
      });

      test('passes through cleaned value when allowlist is empty', () {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: const []));
        final r = ReceiptNormalizer.normalizeToProductGroup(' A * 1 ');
        expect(r, equals('A1'));
      });
    });

    group('normalizeToProductGroups', () {
      test('applies normalizeToProductGroup to all items', () {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: const []));
        final inputs = ['Bread*', 'Milk!', '---'];
        final r = ReceiptNormalizer.normalizeToProductGroups(inputs);
        expect(r, equals(['Bread', 'Milk', '']));
      });

      test('respects allowlist for each item', () {
        ReceiptRuntime.setOptions(
          makeOptionsFromLists(groups: ['BAKERY', 'DAIRY']),
        );
        final inputs = ['BAKERY', 'DAIRY', 'MEAT'];
        final r = ReceiptNormalizer.normalizeToProductGroups(inputs);
        expect(r, equals(['BAKERY', 'DAIRY', '']));
      });
    });

    group('normalizeByAlternativePostfixTexts', () {
      test('returns null for empty list', () {
        final r = ReceiptNormalizer.normalizeByAlternativePostfixTexts([]);
        expect(r, isNull);
      });

      test('returns most frequent allowed normalized group', () {
        ReceiptRuntime.setOptions(
          makeOptionsFromLists(groups: ['BAKERY', 'DAIRY']),
        );

        final alts = ['BAKERY', 'BAKERY', 'Dairy*', 'Unknown!'];

        final r = ReceiptNormalizer.normalizeByAlternativePostfixTexts(alts);
        expect(r, equals('BAKERY'));
      });

      test('returns empty string when all alternatives normalize to empty', () {
        ReceiptRuntime.setOptions(makeOptionsFromLists(groups: ['FOOD']));
        final alts = ['---', '***', '    '];
        final r = ReceiptNormalizer.normalizeByAlternativePostfixTexts(alts);
        expect(r, equals(''));
      });
    });

    group('normalizeByAlternativeTexts', () {
      test('returns most frequent non-empty text', () {
        final alts = ['ItemA', 'ItemB', 'ItemA'];
        final r = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(r, equals('ItemA'));
      });

      test('ignores empty strings when other candidates exist', () {
        final alts = ['Milk', '', 'Milk', ''];
        final r = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(r, equals('Milk'));
      });

      test('returns empty string when all alternatives are empty', () {
        final alts = ['', '', ''];
        final r = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(r, equals(''));
      });

      test('returns null when no alternative texts are provided', () {
        final alts = <String>[];
        final r = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(r, isNull);
      });
    });

    group('calculateTruncatedFrequency', () {
      test(
        'merges truncated leading-token alternatives into longer variant',
        () {
          final values = [
            'Red Carpet',
            'Red Carpet',
            'Red',
            'Rod Capet',
            'Rod Pet',
          ];
          final result = ReceiptNormalizer.calculateTruncatedFrequency(values);

          expect(result.length, 3);
          expect(result['Red Carpet'], equals(60));
          expect(result['Rod Capet'], equals(20));
          expect(result['Rod Pet'], equals(20));
          expect(result.containsKey('Red'), isFalse);
        },
      );

      test('behaves like calculateFrequency when no truncations exist', () {
        final values = ['Apple', 'Banana', 'Apple', 'Cherry'];
        final truncated = ReceiptNormalizer.calculateTruncatedFrequency(values);
        final plain = ReceiptNormalizer.calculateFrequency(values);

        expect(truncated, equals(plain));
      });

      test('returns empty map for empty list', () {
        final result = ReceiptNormalizer.calculateTruncatedFrequency([]);
        expect(result, isEmpty);
      });
    });

    group('calculateFrequency', () {
      test('returns empty map for empty list', () {
        final r = ReceiptNormalizer.calculateFrequency([]);
        expect(r, isEmpty);
      });

      test('returns percentage frequencies rounded to nearest int', () {
        final values = ['a', 'a', 'b'];
        final r = ReceiptNormalizer.calculateFrequency(values);
        expect(r['a'], equals(67));
        expect(r['b'], equals(33));
      });

      test('handles multiple distinct values', () {
        final values = ['x', 'y', 'x', 'z', 'x', 'y'];
        final r = ReceiptNormalizer.calculateFrequency(values);

        expect(r['x'], equals(50));
        expect(r['y'], equals(33));
        expect(r['z'], equals(17));
      });
    });

    group('sortByFrequency', () {
      test('sorts strings by frequency in ascending order', () {
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

      test('returns empty list when given empty list', () {
        final values = <String>[];

        final result = ReceiptNormalizer.sortByFrequency(values);

        expect(result, isEmpty);
      });

      test('contains same elements when all frequencies are equal', () {
        final values = ['apple', 'banana', 'cherry', 'date'];

        final result = ReceiptNormalizer.sortByFrequency(values);

        expect(result.length, 4);
        expect(result.toSet(), equals(values.toSet()));
      });

      test('orders by frequency ascending', () {
        final values = ['x', 'y', 'x', 'z', 'y', 'x', 'w', 'w'];
        final result = ReceiptNormalizer.sortByFrequency(values);
        expect(result.first, anyOf('z', 'w'));
        expect(result.last, equals('x'));
        expect(result.toSet(), equals(values.toSet()));
      });
    });

    group('similarity & stringSimilarity', () {
      test('similarity higher for close variants than unrelated strings', () {
        final close = ReceiptNormalizer.similarity('Coke Zero', 'Coke Zer0');
        final far = ReceiptNormalizer.similarity('Coke Zero', 'Orange Juice');
        expect(close, greaterThan(far));
        expect(close, greaterThanOrEqualTo(70));
      });

      test(
        'stringSimilarity is scaled to [0,1] and correlates with similarity',
        () {
          final s1 = ReceiptNormalizer.stringSimilarity('Milk 1l', 'Milk 1 l');
          final s2 = ReceiptNormalizer.stringSimilarity('Milk 1l', 'Shampoo');

          expect(s1, inInclusiveRange(0.0, 1.0));
          expect(s2, inInclusiveRange(0.0, 1.0));
          expect(s1, greaterThan(s2));
        },
      );
    });

    group('tokensForMatch', () {
      test(
        'tokenization is lowercase-alnum-based with non-alnum separators',
        () {
          final tokens = ReceiptNormalizer.tokensForMatch(
            'cafe-ol 250ml (bio!)',
          );
          expect(tokens, equals({'cafe', 'ol', '250ml', 'bio'}));
        },
      );

      test('collapses multiple spaces and separators', () {
        final tokens = ReceiptNormalizer.tokensForMatch(
          '  organic   milk--1l  ',
        );
        expect(tokens, equals({'organic', 'milk', '1l'}));
      });
    });

    group('specificity', () {
      test('specificity favors more/longer tokens', () {
        final a = ReceiptNormalizer.specificity('milk');
        final b = ReceiptNormalizer.specificity('organic milk 1l');
        expect(b, greaterThan(a));
      });

      test('specificity grows with both token count and character count', () {
        final simple = ReceiptNormalizer.specificity('tea');
        final detailed = ReceiptNormalizer.specificity('green tea bag 20x');
        expect(detailed, greaterThan(simple));
      });
    });
  });
}
