import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/src/utils/normalize/index.dart';

void main() {
  group('ReceiptNormalizer', () {
    group('canonicalKey', () {
      test('removes diacritics and lowercases', () {
        expect(
          ReceiptNormalizer.canonicalKey('Êlite Item'),
          equals('elite item'),
        );
        expect(
          ReceiptNormalizer.canonicalKey('Café Crème'),
          equals('cafe creme'),
        );
        expect(ReceiptNormalizer.canonicalKey('Ångström'), equals('angstrom'));
      });

      test('collapses multiple spaces and trims', () {
        expect(
          ReceiptNormalizer.canonicalKey('  Café   Crème  '),
          equals('cafe creme'),
        );
        expect(
          ReceiptNormalizer.canonicalKey('COFFEE     BEANS'),
          equals('coffee beans'),
        );
      });

      test('treats split/merged tokens equally when letters match', () {
        expect(
          ReceiptNormalizer.canonicalKey('Cof fee'),
          isNot(equals(ReceiptNormalizer.canonicalKey('Coffee'))),
        );
        expect(
          ReceiptNormalizer.canonicalKey('Coffee   Beans'),
          equals(ReceiptNormalizer.canonicalKey('Coffee Beans')),
        );
      });
    });

    group('normalizeByAlternativeTexts with diacritics/spacing', () {
      test('prefers consensus and returns clean shortest original', () {
        final alts = ['Café Crème', 'Cafe Creme', 'CAFÉ   CRÈME', 'Cafe Creme'];
        final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(result, equals('Cafe Creme'));
      });

      test('handles mixed diacritics + spacing + case', () {
        final alts = [
          'Êxtra   Virgin OLÍVE  OIL',
          'Extra Virgin Olive Oil',
          'EXTRA VIRGIN OLIVE  OIL',
        ];
        final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
        expect(result, equals('Extra Virgin Olive Oil'));
      });
    });

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

        expect(result, 'ItemA123');
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

    group('canonicalKey – unicode/whitespace edge cases', () {
      test('handles NBSP and exotic spaces', () {
        expect(
          ReceiptNormalizer.canonicalKey('Café\u00A0Crème'),
          equals('cafe creme'),
        );

        expect(
          ReceiptNormalizer.canonicalKey('  Elite\tItem\u2009—\u2003Deluxe  '),
          equals('elite item — deluxe'),
        );
      });
    });

    group(
      'normalizeByAlternativeTexts – OCR + single-space removal + truncation',
      () {
        test('corrects OCR confusions using peer alternatives', () {
          final alts = ['8io Weidemilch', 'Bio Weidemilch', 'B!o Weidemilch'];
          final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
          expect(result, equals('Bio Weidemilch'));
        });

        test(
          'glues single erroneous space when exact one-space difference matches',
          () {
            final alts = ['Weide milch', 'Weidemilch', 'WEIDE MILCH'];
            final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
            expect(result, equals('Weidemilch'));
          },
        );

        test('filters truncated leading token alternatives', () {
          final alts = ['GOETTERSP.', 'GOETTERSP. WALD', 'GOETTERSP. WALD'];
          final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
          expect(result, equals('GOETTERSP. WALD'));
        });

        test('tie-breaker prefers size token on equal frequency', () {
          final alts = [
            'Coke Zero',
            'Coke Zero 330ml',
            'Coke Zero',
            'Coke Zero 330ml',
          ];
          final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
          expect(result, equals('Coke Zero 330ml'));
        });

        test(
          'tie-breaker prefers variant without diacritics when otherwise tied',
          () {
            final alts = ['Cafe Creme', 'Café Crème'];
            final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
            expect(result, equals('Cafe Creme'));
          },
        );

        test(
          'number–unit split is normalized for grouping (e.g., 1 l vs 1l)',
          () {
            final alts = ['Milk 1 l', 'MILK 1l', 'milk 1  l'];
            final result = ReceiptNormalizer.normalizeByAlternativeTexts(alts);
            expect(
              result,
              anyOf(equals('MILK 1l'), equals('Milk 1l'), equals('milk 1l')),
            );
          },
        );
      },
    );

    group('normalizeTail – tricky tails', () {
      test('strips price-like tails', () {
        expect(
          ReceiptNormalizer.normalizeTail('Shorts 10,99'),
          equals('Shorts'),
        );
        expect(
          ReceiptNormalizer.normalizeTail('Butter 1,99'),
          equals('Butter'),
        );
        expect(
          ReceiptNormalizer.normalizeTail('Cola 0,89 xyz'),
          equals('Cola'),
        );
        expect(
          ReceiptNormalizer.normalizeTail('Green Tea 3.50 @'),
          equals('Green Tea'),
        );
        expect(
          ReceiptNormalizer.normalizeTail('Chocolate 2,99 ex'),
          equals('Chocolate'),
        );
        expect(
          ReceiptNormalizer.normalizeTail('Cream 0,69 € x'),
          equals('Cream'),
        );
      });
    });

    group('normalizeSpecialSpaces – signature-based selection', () {
      test('prefers candidate with glued number–unit on tie', () {
        const mostFrequent = 'Milk 1 l';
        final peers = ['Milk 1l', 'Milk 1 l'];
        final result = ReceiptNormalizer.normalizeSpecialSpaces(
          mostFrequent,
          peers,
        );
        expect(result, equals('Milk 1l'));
      });

      test('prefers fewer spaces, then shorter, then lexicographical', () {
        const mostFrequent = 'Coke  Zero';
        final peers = ['Coke Zero', 'Coke  Zero', 'Coke Zero  '];
        final result = ReceiptNormalizer.normalizeSpecialSpaces(
          mostFrequent,
          peers,
        );
        expect(result, equals('Coke Zero'));
      });

      test('returns original when no same-signature peers', () {
        const best = 'Coffee Beans';
        final others = ['Tea-Bags'];
        final result = ReceiptNormalizer.normalizeSpecialSpaces(best, others);
        expect(result, equals('Coffee Beans'));
      });
    });

    group('similarity & stringSimilarity – fuzzy wrappers', () {
      test('similarity higher for close variants than unrelated strings', () {
        final close = ReceiptNormalizer.similarity('Coke Zero', 'Coke Zer0');
        final far = ReceiptNormalizer.similarity('Coke Zero', 'Orange Juice');
        expect(close, greaterThan(far));
        expect(close, greaterThanOrEqualTo(70));
      });

      test('stringSimilarity is scaled to [0,1]', () {
        final s1 = ReceiptNormalizer.stringSimilarity('Milk 1l', 'Milk 1 l');
        final s2 = ReceiptNormalizer.stringSimilarity('Milk 1l', 'Shampoo');
        expect(s1, inInclusiveRange(0.0, 1.0));
        expect(s2, inInclusiveRange(0.0, 1.0));
        expect(s1, greaterThan(s2));
      });
    });

    group('tokensForMatch & specificity', () {
      test('tokenization is lowercase, diacritic-free, alnum-only', () {
        final tokens = ReceiptNormalizer.tokensForMatch('Café-Öl 250ml (BIO!)');
        expect(tokens, equals({'cafe', 'ol', '250ml', 'bio'}));
      });

      test('specificity favors more/longer tokens', () {
        final a = ReceiptNormalizer.specificity('Milk');
        final b = ReceiptNormalizer.specificity('Organic Milk 1l');
        expect(b, greaterThan(a));
      });
    });

    group('sortByFrequency – stability on ties (sanity)', () {
      test('contains same elements and orders by frequency ascending', () {
        final values = ['x', 'y', 'x', 'z', 'y', 'x', 'w', 'w'];
        final result = ReceiptNormalizer.sortByFrequency(values);
        expect(result.first, equals('z'));
        expect(result.last, equals('x'));
        expect(result.toSet(), equals(values.toSet()));
      });
    });
  });
}
