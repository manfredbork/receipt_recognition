import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';

void main() {
  group('ReceiptParserJa - row grouping parser', () {
    late ReceiptOptions jaOptions;

    setUp(() {
      jaOptions = ReceiptOptions.japanese();
      ReceiptTextProcessor.debugRunSynchronouslyForTests = true;
    });

    RecognizedText buildRecognizedText(List<_LineSpec> specs) {
      final lines = <TextLine>[];
      for (final spec in specs) {
        lines.add(ReceiptTextLine(text: spec.text, boundingBox: spec.rect));
      }
      final block = _FakeTextBlock(lines);
      return _FakeRecognizedText([block]);
    }

    group('script flag', () {
      test('japanese() options set script to japanese', () {
        expect(jaOptions.script, TextRecognitionScript.japanese);
      });

      test('defaults() options set script to null (geometric parser)', () {
        final defaults = ReceiptOptions.defaults();
        expect(defaults.script, isNull);
      });
    });

    group('Separate product name and price lines', () {
      test('recognizes product name and price on separate lines', () async {
        final text = buildRecognizedText([
          _LineSpec('イオン', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('パン', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥348', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('お預かり', Rect.fromLTWH(50, 170, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'イオン');
        expect(receipt.positions, hasLength(2));
        expect(receipt.total?.value, 348.0);
      });

      test('recognizes yen-suffixed prices', () async {
        final text = buildRecognizedText([
          _LineSpec('セブンイレブン', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('おにぎり', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('130円', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('130円', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'セブンイレブン');
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 130.0);
      });

      test('recognizes comma-separated prices', () async {
        final text = buildRecognizedText([
          _LineSpec('ライフ', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('お刺身盛合せ', Rect.fromLTWH(50, 50, 150, 30)),
          _LineSpec('¥1,280', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥1,280', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'ライフ');
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 1280.0);
      });
    });

    group('Inline prices (Japanese receipt specific)', () {
      test('recognizes product and price on the same TextLine', () async {
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ ¥702', Rect.fromLTWH(50, 50, 300, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 702.0);
        expect(
          receipt.positions.first.product.text,
          contains('TTOもちチーズ'),
        );
        expect(receipt.total?.value, 702.0);
      });

      test('handles prices with marker suffix', () async {
        final text = buildRecognizedText([
          _LineSpec(
            'TTOもちチーズ 明6個 ¥702※',
            Rect.fromLTWH(50, 50, 350, 30),
          ),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 702.0);
        expect(receipt.total?.value, 702.0);
      });
    });

    group('Discount line handling', () {
      test('recognizes negative discount lines', () async {
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('値引', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('-100', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥602', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(2));

        final item = receipt.positions.first;
        expect(item.price.value, 702.0);

        final discount = receipt.positions[1];
        expect(discount.price.value, -100.0);

        expect(receipt.total?.value, 602.0);
      });
    });

    group('Total vs subtotal distinction', () {
      test('uses total when both subtotal and total are present', () async {
        final text = buildRecognizedText([
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥200', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('パン', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥300', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('小計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥500', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 170, 100, 30)),
          _LineSpec('¥550', Rect.fromLTWH(250, 170, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(2));
        // The last total label's amount is used
        expect(receipt.total?.value, 550.0);
      });
    });

    group('Date recognition', () {
      test('recognizes kanji date format', () async {
        final text = buildRecognizedText([
          _LineSpec('ローソン', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('2025年1月15日', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('お茶', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate?.value, DateTime.utc(2025, 1, 15));
      });

      test('recognizes Japanese era (wareki) date format', () async {
        final text = buildRecognizedText([
          _LineSpec('ファミリーマート', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('令和7年1月15日', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('おにぎり', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate?.value, DateTime.utc(2025, 1, 15));
      });

      test('recognizes slash-delimited date format', () async {
        final text = buildRecognizedText([
          _LineSpec('2025/02/08', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('お茶', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate?.value, DateTime.utc(2025, 2, 8));
      });
    });

    group('Full-width character normalization', () {
      test('normalizes full-width digits and symbols', () async {
        final text = buildRecognizedText([
          _LineSpec('イオン', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('￥１９８', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('￥１９８', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 198.0);
      });
    });

    group('Stop keywords', () {
      test('stops parsing at stop keywords', () async {
        final text = buildRecognizedText([
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('お預かり', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥500', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(1));
      });

      test('stops parsing at PayPay line', () async {
        final text = buildRecognizedText([
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('PayPay', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, hasLength(1));
        expect(receipt.total?.value, 198.0);
      });
    });

    group('Empty and edge cases', () {
      test('returns empty receipt for empty text', () async {
        final text = _FakeRecognizedText([]);
        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, isEmpty);
        expect(receipt.total, isNull);
      });

      test('skips lines without prices', () async {
        final text = buildRecognizedText([
          _LineSpec('店舗コード 12345', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('いらっしゃいませ', Rect.fromLTWH(50, 50, 200, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, isEmpty);
      });
    });

    group('Default parser (non-Japanese) compatibility', () {
      test('uses existing parser when script=null', () async {
        final deOptions = ReceiptOptions.defaults();
        expect(deOptions.script, isNull);

        final text = buildRecognizedText([
          _LineSpec('Aldi', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('Milch', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('1,99', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('Summe', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('1,99', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('Bar', Rect.fromLTWH(50, 130, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, deOptions);
        expect(receipt.store?.value, 'Aldi');
        expect(receipt.positions, hasLength(1));
        expect(receipt.positions.first.price.value, 1.99);
      });
    });

    group('Real receipt pattern (Gindaco-style)', () {
      test('recognizes inline product+price, discount, and total', () async {
        final text = buildRecognizedText([
          _LineSpec('銀だこ酒場', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('2026年2月8日', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec(
            'TTOもちチーズ 明6個 ¥702※',
            Rect.fromLTWH(50, 90, 350, 30),
          ),
          _LineSpec('@100x 1', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('-100', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 170, 100, 30)),
          _LineSpec('¥602', Rect.fromLTWH(250, 170, 80, 30)),
          _LineSpec('PayPay', Rect.fromLTWH(50, 210, 100, 30)),
          _LineSpec('¥602', Rect.fromLTWH(250, 210, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);

        // Date is recognized
        expect(receipt.purchaseDate?.value, DateTime.utc(2026, 2, 8));

        // Product lines are recognized
        expect(receipt.positions.isNotEmpty, isTrue);

        // Total is recognized
        expect(receipt.total?.value, 602.0);

        // Lines after PayPay are excluded
        final allPrices = receipt.positions.map((p) => p.price.value).toList();
        expect(allPrices, isNot(contains(602.0)));
      });
    });

    group('Store name fallback — structural detection of unregistered names', () {
      test('detects unregistered English store name from first line', () async {
        final text = buildRecognizedText([
          _LineSpec('TSUKIJI', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('GINDACOSAKABA', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec(
            'TTOもちチーズ ¥702',
            Rect.fromLTWH(50, 90, 350, 30),
          ),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'TSUKIJI');
      });

      test('skips phone number line and uses next line as store', () async {
        final text = buildRecognizedText([
          _LineSpec('03-1234-5678', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('GINDACO SAKABA', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 130, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'GINDACO SAKABA');
      });

      test('skips pure digit strings', () async {
        // 0001 → standalonePrice returns null due to >= 10 threshold,
        // so it's not a price line, but skipped by pure-digit check.
        final text = buildRecognizedText([
          _LineSpec('0001', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('SHOP NAME', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'SHOP NAME');
      });

      test('skips lines with 2 or fewer characters', () async {
        final text = buildRecognizedText([
          _LineSpec('AB', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('MY STORE', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'MY STORE');
      });
    });

    group('Total estimation — infer total from item sum without label', () {
      test('estimates total from position sum when label is missing', () async {
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('値引', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('-100', Rect.fromLTWH(250, 90, 80, 30)),
          // ¥602 exists without a total label
          _LineSpec('¥602', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('PayPay', Rect.fromLTWH(50, 170, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.total?.value, 602.0);
      });

      test('estimates total even when sum amount is not in OCR', () async {
        final text = buildRecognizedText([
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥200', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('パン', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('お預かり', Rect.fromLTWH(50, 130, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        // 200 + 150 = 350
        expect(receipt.total?.value, 350.0);
      });
    });

    group('Garbled ¥ — price recognition when OCR reads ¥ as 4', () {
      test('recognizes 4702% as ¥702', () async {
        // OCR garbles: ¥→4, ※→%
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('4702%', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions.first.price.value, 702.0);
      });

      test('treats 4702 without trailing artifact as normal price',
          () async {
        // Without trailing artifact, not treated as garbled
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('4702', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥4702', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions.first.price.value, 4702.0);
      });

      test('real device OCR pattern: 4702% + -100 estimates total 602',
          () async {
        // Reproduce real OCR output
        final text = buildRecognizedText([
          _LineSpec('TSUKIJI', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('GINDACOSAKABA', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('TTO5-`BA6', Rect.fromLTWH(50, 90, 200, 30)),
          _LineSpec('4702%', Rect.fromLTWH(250, 90, 80, 30)),
          _LineSpec('e100x', Rect.fromLTWH(50, 130, 100, 30)),
          _LineSpec('-100', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('602)', Rect.fromLTWH(250, 170, 80, 30)),
          _LineSpec('PayPay', Rect.fromLTWH(50, 210, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.store?.value, 'TSUKIJI');
        expect(receipt.positions.first.price.value, 702.0);
        expect(receipt.positions[1].price.value, -100.0);
        // 702 + (-100) = 602
        expect(receipt.total?.value, 602.0);
      });
    });

    group('Date garbled fallback — recognizing garbled dates in OCR', () {
      test('parses garbled year/month/day', () async {
        final text = buildRecognizedText([
          // "2026年2月8日" is garbled by OCR
          _LineSpec(
            '20264# 2A 8A(A)17H34A000101',
            Rect.fromLTWH(50, 10, 400, 30),
          ),
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate?.value, DateTime.utc(2026, 2, 8));
      });

      test('normal date takes priority over garbled fallback', () async {
        final text = buildRecognizedText([
          _LineSpec('2025年3月15日', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate?.value, DateTime.utc(2025, 3, 15));
      });

      test('rejects out-of-range month/day in garbled fallback', () async {
        final text = buildRecognizedText([
          // month=13 is out of range
          _LineSpec(
            '20264# 13A 8A(A)17H34A',
            Rect.fromLTWH(50, 10, 400, 30),
          ),
          _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
          _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.purchaseDate, isNull);
      });
    });
  });
}

/// Line spec for tests
class _LineSpec {
  final String text;
  final Rect rect;
  const _LineSpec(this.text, this.rect);
}

/// Fake RecognizedText for tests
class _FakeRecognizedText implements RecognizedText {
  @override
  final String text;

  @override
  final List<TextBlock> blocks;

  _FakeRecognizedText(this.blocks)
    : text = blocks.map((b) => b.text).join('\n');
}

/// Fake TextBlock for tests
class _FakeTextBlock implements TextBlock {
  @override
  final String text;

  @override
  final List<TextLine> lines;

  @override
  final Rect boundingBox;

  @override
  final List<String> recognizedLanguages;

  @override
  final List<Point<int>> cornerPoints;

  _FakeTextBlock(this.lines)
    : text = lines.map((l) => l.text).join('\n'),
      boundingBox =
          lines.isEmpty
              ? Rect.zero
              : lines
                  .map((l) => l.boundingBox)
                  .reduce((a, b) => a.expandToInclude(b)),
      recognizedLanguages = const [],
      cornerPoints = const [];
}
