import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';

void main() {
  group('ReceiptParserJa - 行グルーピングパーサー', () {
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

    group('script フラグ', () {
      test('japanese() オプションで script が japanese', () {
        expect(jaOptions.script, TextRecognitionScript.japanese);
      });

      test('defaults() オプションで script が null（geometric パーサー）', () {
        final defaults = ReceiptOptions.defaults();
        expect(defaults.script, isNull);
      });
    });

    group('分離された商品名・金額行（既存テストと同等）', () {
      test('商品名と金額が別行の場合に正しく認識する', () async {
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

      test('円記号付き金額を認識する', () async {
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

      test('カンマ区切りの金額を認識する', () async {
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

    group('同一行に埋め込まれた金額（日本語レシート特有）', () {
      test('商品名と金額が同じTextLineの場合に認識する', () async {
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

      test('※マーカー付き金額を正しく処理する', () async {
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

    group('割引行の処理', () {
      test('マイナス割引行を認識する', () async {
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

    group('合計と小計の区別', () {
      test('小計の後に合計がある場合、合計を使用する', () async {
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
        // 最後の合計ラベルの金額が使われる
        expect(receipt.total?.value, 550.0);
      });
    });

    group('日付認識', () {
      test('漢字日付を認識する', () async {
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

      test('和暦日付を認識する', () async {
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

      test('スラッシュ区切り日付を認識する', () async {
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

    group('全角文字の正規化', () {
      test('全角数字・記号を正規化して認識する', () async {
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

    group('ストップキーワード', () {
      test('ストップキーワードで解析を停止する', () async {
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

      test('PayPay行で解析が停止する', () async {
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

    group('空・エッジケース', () {
      test('空のテキストで空のレシートを返す', () async {
        final text = _FakeRecognizedText([]);
        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, isEmpty);
        expect(receipt.total, isNull);
      });

      test('金額がない行はスキップされる', () async {
        final text = buildRecognizedText([
          _LineSpec('店舗コード 12345', Rect.fromLTWH(50, 10, 200, 30)),
          _LineSpec('いらっしゃいませ', Rect.fromLTWH(50, 50, 200, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.positions, isEmpty);
      });
    });

    group('デフォルトパーサー（非日本語）との互換性', () {
      test('script=null の場合、既存パーサーを使用する', () async {
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

    group('実際のレシートパターン（銀だこ風）', () {
      test('商品+金額が同一行 + 割引 + 合計を正しく認識する', () async {
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

        // 日付が認識されること
        expect(receipt.purchaseDate?.value, DateTime.utc(2026, 2, 8));

        // 商品行が認識されること
        expect(receipt.positions.isNotEmpty, isTrue);

        // 合計が認識されること
        expect(receipt.total?.value, 602.0);

        // PayPay行以降は含まれないこと
        final allPrices = receipt.positions.map((p) => p.price.value).toList();
        expect(allPrices, isNot(contains(602.0)));
      });
    });

    group('店名 fallback — 辞書にない英字店名の構造検出', () {
      test('辞書未登録の英字店名を最初の行から検出する', () async {
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

      test('電話番号行はスキップして次の行を店名にする', () async {
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

      test('純粋な数字列はスキップする', () async {
        // 0001 → standalonePrice は >= 10 チェックで null を返すので
        // price 行にはならないが、pure-digit チェックでスキップされる。
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

      test('2文字以下の短い行はスキップする', () async {
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

    group('合計推定 — ラベルなしでアイテム合算から total を推定', () {
      test('合計ラベルなしで positions の合算から total を推定する', () async {
        final text = buildRecognizedText([
          _LineSpec('TTOもちチーズ', Rect.fromLTWH(50, 50, 200, 30)),
          _LineSpec('¥702', Rect.fromLTWH(250, 50, 80, 30)),
          _LineSpec('値引', Rect.fromLTWH(50, 90, 100, 30)),
          _LineSpec('-100', Rect.fromLTWH(250, 90, 80, 30)),
          // ¥602 は合計ラベルなしで存在する
          _LineSpec('¥602', Rect.fromLTWH(250, 130, 80, 30)),
          _LineSpec('PayPay', Rect.fromLTWH(50, 170, 100, 30)),
        ]);

        final receipt =
            await ReceiptTextProcessor.processText(text, jaOptions);
        expect(receipt.total?.value, 602.0);
      });

      test('OCR に合算額が見つからない場合でも total を推定する', () async {
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

    group('garbled ¥ — OCRが¥を4として読む場合の金額認識', () {
      test('4702% を ¥702※ として認識する', () async {
        // OCR: ¥→4, ※→% でガーブル
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

      test('末尾 artifact なしの 4702 は通常の price として扱う',
          () async {
        // trailing artifact がなければガーブルとは判定しない
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

      test('実機OCRパターン: 4702% + -100 で total 602 を推定する',
          () async {
        // 実際のOCR出力を再現
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

    group('日付ガーブル fallback — OCRでガーブルされた日付の認識', () {
      test('ガーブルされた年月日をパースする', () async {
        final text = buildRecognizedText([
          // "2026年2月8日" がガーブル
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

      test('正常な日付が優先されガーブル fallback は使われない', () async {
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

      test('範囲外の月日はガーブル fallback でも拒否される', () async {
        final text = buildRecognizedText([
          // 月=13 は範囲外
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
