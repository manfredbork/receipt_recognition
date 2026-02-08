import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';

void main() {
  group('ReceiptFormatter - 日本語日付パース', () {
    group('parseKanjiDate', () {
      test('標準形式 2025年1月15日', () {
        final dt = ReceiptFormatter.parseKanjiDate('2025年1月15日');
        expect(dt, DateTime.utc(2025, 1, 15));
      });

      test('スペースあり 2025 年 1 月 15 日', () {
        final dt = ReceiptFormatter.parseKanjiDate('2025 年 1 月 15 日');
        expect(dt, DateTime.utc(2025, 1, 15));
      });

      test('2桁月日 2025年12月31日', () {
        final dt = ReceiptFormatter.parseKanjiDate('2025年12月31日');
        expect(dt, DateTime.utc(2025, 12, 31));
      });

      test('無効な日付は null', () {
        expect(ReceiptFormatter.parseKanjiDate('abc'), isNull);
        expect(ReceiptFormatter.parseKanjiDate('2025年13月1日'), isNull);
      });
    });

    group('parseJapaneseEraDate', () {
      test('令和7年1月15日 → 2025-01-15', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('令和7年1月15日');
        expect(dt, DateTime.utc(2025, 1, 15));
      });

      test('平成31年4月30日 → 2019-04-30', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('平成31年4月30日');
        expect(dt, DateTime.utc(2019, 4, 30));
      });

      test('昭和64年1月7日 → 1989-01-07', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('昭和64年1月7日');
        expect(dt, DateTime.utc(1989, 1, 7));
      });

      test('大正15年12月25日 → 1926-12-25', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('大正15年12月25日');
        expect(dt, DateTime.utc(1926, 12, 25));
      });

      test('明治45年7月30日 → 1912-07-30', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('明治45年7月30日');
        expect(dt, DateTime.utc(1912, 7, 30));
      });

      test('スペースあり 令和 7 年 1 月 15 日', () {
        final dt = ReceiptFormatter.parseJapaneseEraDate('令和 7 年 1 月 15 日');
        expect(dt, DateTime.utc(2025, 1, 15));
      });

      test('無効な元号は null', () {
        expect(ReceiptFormatter.parseJapaneseEraDate('安政5年1月1日'), isNull);
      });

      test('無効な入力は null', () {
        expect(ReceiptFormatter.parseJapaneseEraDate('abc'), isNull);
      });
    });
  });

  group('ReceiptFormatter - JPYフォーマット', () {
    setUp(() {
      Intl.defaultLocale = 'ja_JP';
    });

    tearDown(() {
      Intl.defaultLocale = 'en_US';
    });

    test('decimalDigits: 0 で整数フォーマット', () {
      expect(ReceiptFormatter.format(198, decimalDigits: 0), '198');
    });

    test('桁区切り', () {
      expect(ReceiptFormatter.format(1280, decimalDigits: 0), '1,280');
    });
  });

  group('ReceiptNormalizer - 全角→半角変換', () {
    test('全角数字 → 半角数字', () {
      expect(ReceiptNormalizer.normalizeFullWidth('１２３'), '123');
    });

    test('全角英字 → 半角英字', () {
      expect(ReceiptNormalizer.normalizeFullWidth('ＡＢＣ'), 'ABC');
    });

    test('全角円記号 → 半角', () {
      expect(ReceiptNormalizer.normalizeFullWidth('￥１，２８０'), '¥1,280');
    });

    test('全角スペース → 半角スペース', () {
      expect(ReceiptNormalizer.normalizeFullWidth('Ａ　Ｂ'), 'A B');
    });

    test('半角文字はそのまま', () {
      expect(ReceiptNormalizer.normalizeFullWidth('ABC123'), 'ABC123');
    });

    test('日本語文字はそのまま', () {
      expect(ReceiptNormalizer.normalizeFullWidth('合計'), '合計');
    });

    test('混合文字列', () {
      expect(ReceiptNormalizer.normalizeFullWidth('合計　￥１，２８０'), '合計 ¥1,280');
    });
  });

  group('ReceiptOptions - 日本語デフォルト', () {
    test('japanese()ファクトリでインスタンス生成', () {
      final opts = ReceiptOptions.japanese();
      expect(opts.storeNames.mapping, isNotEmpty);
      expect(opts.totalLabels.mapping, isNotEmpty);
      expect(opts.ignoreKeywords.keywords, isNotEmpty);
      expect(opts.stopKeywords.keywords, isNotEmpty);
    });

    test('日本の主要店名が含まれている', () {
      final opts = ReceiptOptions.japanese();
      final stores = opts.storeNames.mapping.values.toSet();
      expect(stores, contains('イオン'));
      expect(stores, contains('セブンイレブン'));
      expect(stores, contains('ローソン'));
      expect(stores, contains('ファミリーマート'));
    });

    test('店名のエイリアスが正しい', () {
      final opts = ReceiptOptions.japanese();
      expect(opts.storeNames.detect('AEON'), 'イオン');
      expect(opts.storeNames.detect('LAWSON'), 'ローソン');
      expect(opts.storeNames.detect('FamilyMart'), 'ファミリーマート');
    });

    test('合計ラベルが含まれている', () {
      final opts = ReceiptOptions.japanese();
      final labels = opts.totalLabels.mapping.values.toSet();
      expect(labels, contains('合計'));
      expect(labels, contains('税込合計'));
      expect(labels, contains('小計'));
    });

    test('ストップキーワードが含まれている', () {
      final opts = ReceiptOptions.japanese();
      final stops = opts.stopKeywords.keywords;
      expect(stops, contains('お預かり'));
      expect(stops, contains('現金'));
    });

    test('tuning が正しく設定されている', () {
      final opts = ReceiptOptions.japanese();
      expect(opts.tuning.optimizerTotalTolerance, 1.0);
      expect(opts.tuning.optimizerUnrecognizedProductName, '未認識商品');
    });

    test('defaults() はドイツ語設定のまま', () {
      final opts = ReceiptOptions.defaults();
      final stores = opts.storeNames.mapping.values.toSet();
      expect(stores, contains('Aldi'));
      expect(stores, contains('Lidl'));
    });
  });

  group('kReceiptDefaultOptionsJa', () {
    test('マップに必要なキーが存在する', () {
      expect(kReceiptDefaultOptionsJa, containsPair('storeNames', isA<Map>()));
      expect(kReceiptDefaultOptionsJa, containsPair('totalLabels', isA<Map>()));
      expect(
        kReceiptDefaultOptionsJa,
        containsPair('ignoreKeywords', isA<List>()),
      );
      expect(
        kReceiptDefaultOptionsJa,
        containsPair('stopKeywords', isA<List>()),
      );
      expect(kReceiptDefaultOptionsJa, containsPair('tuning', isA<Map>()));
    });
  });

  group('パーサー統合テスト - 日本語レシート', () {
    late ReceiptOptions jaOptions;

    setUp(() {
      jaOptions = ReceiptOptions.japanese();
      ReceiptTextProcessor.debugRunSynchronouslyForTests = true;
    });

    /// ReceiptTextLine を使った TextBlock/RecognizedText の生成ヘルパー
    RecognizedText buildRecognizedText(List<_LineSpec> specs) {
      final lines = <TextLine>[];
      for (final spec in specs) {
        lines.add(ReceiptTextLine(text: spec.text, boundingBox: spec.rect));
      }
      final block = _FakeTextBlock(lines);
      return _FakeRecognizedText([block]);
    }

    test('日本円金額を認識する', () async {
      // 左側に商品名、右側に金額、フッター行を追加
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

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.store?.value, 'イオン');
      expect(receipt.positions, hasLength(2));
      expect(receipt.total?.value, 348.0);
    });

    test('円記号付き金額を認識する', () async {
      final text = buildRecognizedText([
        _LineSpec('セブンイレブン', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('おにぎり', Rect.fromLTWH(50, 50, 100, 30)),
        _LineSpec('130円', Rect.fromLTWH(250, 50, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('130円', Rect.fromLTWH(250, 90, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.store?.value, 'セブンイレブン');
      expect(receipt.positions, hasLength(1));
      expect(receipt.positions.first.price.value, 130.0);
    });

    test('カンマ桁区切りの金額を認識する', () async {
      final text = buildRecognizedText([
        _LineSpec('ライフ', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('お刺身盛合せ', Rect.fromLTWH(50, 50, 150, 30)),
        _LineSpec('¥1,280', Rect.fromLTWH(250, 50, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('¥1,280', Rect.fromLTWH(250, 90, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.store?.value, 'ライフ');
      expect(receipt.positions, hasLength(1));
      expect(receipt.positions.first.price.value, 1280.0);
    });

    test('漢字日付を認識する', () async {
      final text = buildRecognizedText([
        _LineSpec('ローソン', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('2025年1月15日', Rect.fromLTWH(50, 50, 200, 30)),
        _LineSpec('お茶', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
        _LineSpec('¥150', Rect.fromLTWH(250, 130, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.purchaseDate?.value, DateTime.utc(2025, 1, 15));
    });

    test('和暦日付を認識する', () async {
      final text = buildRecognizedText([
        _LineSpec('ファミリーマート', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('令和7年1月15日', Rect.fromLTWH(50, 50, 200, 30)),
        _LineSpec('おにぎり', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('¥150', Rect.fromLTWH(250, 90, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 130, 100, 30)),
        _LineSpec('¥150', Rect.fromLTWH(250, 130, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.purchaseDate?.value, DateTime.utc(2025, 1, 15));
    });

    test('全角テキストを正規化して認識する', () async {
      final text = buildRecognizedText([
        _LineSpec('イオン', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
        _LineSpec('￥１９８', Rect.fromLTWH(250, 50, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('￥１９８', Rect.fromLTWH(250, 90, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      expect(receipt.positions, hasLength(1));
      expect(receipt.positions.first.price.value, 198.0);
    });

    test('ストップキーワードで解析を停止する', () async {
      final text = buildRecognizedText([
        _LineSpec('イオン', Rect.fromLTWH(50, 10, 200, 30)),
        _LineSpec('牛乳', Rect.fromLTWH(50, 50, 100, 30)),
        _LineSpec('¥198', Rect.fromLTWH(250, 50, 80, 30)),
        _LineSpec('合計', Rect.fromLTWH(50, 90, 100, 30)),
        _LineSpec('¥198', Rect.fromLTWH(250, 90, 80, 30)),
        _LineSpec('お預かり', Rect.fromLTWH(50, 130, 100, 30)),
        _LineSpec('¥500', Rect.fromLTWH(250, 130, 80, 30)),
      ]);

      final receipt = await ReceiptTextProcessor.processText(text, jaOptions);
      // お預かりの ¥500 はpositionsに含まれない
      expect(receipt.positions, hasLength(1));
    });
  });
}

/// テスト用のライン仕様
class _LineSpec {
  final String text;
  final Rect rect;
  const _LineSpec(this.text, this.rect);
}

/// テスト用の RecognizedText 実装
class _FakeRecognizedText implements RecognizedText {
  @override
  final String text;

  @override
  final List<TextBlock> blocks;

  _FakeRecognizedText(this.blocks)
    : text = blocks.map((b) => b.text).join('\n');
}

/// テスト用の TextBlock 実装
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
