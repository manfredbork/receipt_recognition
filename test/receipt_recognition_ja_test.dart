import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  group('日本語拡張テスト', () {
    group('ReceiptFormatter - 日本語日付パース', () {
      group('parseKanjiDate', () {
        test('標準的な漢字日付をパースする', () {
          final dt = ReceiptFormatter.parseKanjiDate('2025年1月15日');
          expect(dt, DateTime.utc(2025, 1, 15));
        });

        test('スペースを含む漢字日付をパースする', () {
          final dt = ReceiptFormatter.parseKanjiDate('2025 年 1 月 15 日');
          expect(dt, DateTime.utc(2025, 1, 15));
        });

        test('2桁月日をパースする', () {
          final dt = ReceiptFormatter.parseKanjiDate('2024年12月31日');
          expect(dt, DateTime.utc(2024, 12, 31));
        });

        test('無効な入力でnullを返す', () {
          expect(ReceiptFormatter.parseKanjiDate('abc'), isNull);
          expect(ReceiptFormatter.parseKanjiDate('2025-01-15'), isNull);
          expect(ReceiptFormatter.parseKanjiDate(''), isNull);
        });
      });

      group('parseJapaneseEraDate', () {
        test('令和の日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('令和7年1月15日');
          expect(dt, DateTime.utc(2025, 1, 15));
        });

        test('平成の日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('平成31年4月30日');
          expect(dt, DateTime.utc(2019, 4, 30));
        });

        test('昭和の日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('昭和64年1月7日');
          expect(dt, DateTime.utc(1989, 1, 7));
        });

        test('大正の日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('大正15年12月25日');
          expect(dt, DateTime.utc(1926, 12, 25));
        });

        test('明治の日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('明治45年7月30日');
          expect(dt, DateTime.utc(1912, 7, 30));
        });

        test('スペースを含む和暦日付をパースする', () {
          final dt = ReceiptFormatter.parseJapaneseEraDate('令和 7 年 1 月 15 日');
          expect(dt, DateTime.utc(2025, 1, 15));
        });

        test('無効な入力でnullを返す', () {
          expect(ReceiptFormatter.parseJapaneseEraDate('abc'), isNull);
          expect(ReceiptFormatter.parseJapaneseEraDate('令和'), isNull);
          expect(ReceiptFormatter.parseJapaneseEraDate(''), isNull);
        });
      });
    });

    group('ReceiptFormatter - JPYフォーマット', () {
      setUp(() {
        Intl.defaultLocale = 'ja_JP';
      });

      test('decimalDigits: 0 で整数フォーマット', () {
        expect(ReceiptFormatter.format(198, decimalDigits: 0), '198');
      });

      test('大きな数値を桁区切りでフォーマット', () {
        expect(ReceiptFormatter.format(1280, decimalDigits: 0), '1,280');
      });

      test('decimalDigits: 2 で小数点以下2桁', () {
        Intl.defaultLocale = 'en_US';
        expect(ReceiptFormatter.format(1.99), '1.99');
      });
    });

    group('ReceiptNormalizer - 全角→半角変換', () {
      test('全角数字を半角に変換する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('１２３'), '123');
      });

      test('全角英字を半角に変換する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('ＡＢＣ'), 'ABC');
      });

      test('全角記号を半角に変換する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('￥'), '¥');
      });

      test('全角スペースを半角スペースに変換する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('\u3000'), ' ');
      });

      test('混在した全角半角文字列を変換する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('￥１，２８０'), '¥1,280');
      });

      test('半角文字はそのまま保持する', () {
        expect(ReceiptNormalizer.normalizeFullWidth('abc123'), 'abc123');
      });

      test('日本語文字（ひらがな・カタカナ・漢字）は変換しない', () {
        expect(ReceiptNormalizer.normalizeFullWidth('合計'), '合計');
        expect(ReceiptNormalizer.normalizeFullWidth('イオン'), 'イオン');
      });

      test('空文字列の場合は空文字列を返す', () {
        expect(ReceiptNormalizer.normalizeFullWidth(''), '');
      });
    });

    group('ReceiptOptions - 日本語デフォルト', () {
      test('japanese()ファクトリで日本語デフォルトオプションを生成する', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.storeNames.mapping, isNotEmpty);
        expect(opts.totalLabels.mapping, isNotEmpty);
        expect(opts.ignoreKeywords.keywords, isNotEmpty);
        expect(opts.stopKeywords.keywords, isNotEmpty);
      });

      test('日本語店名が含まれている', () {
        final opts = ReceiptOptions.japanese();
        final storeKeys = opts.storeNames.mapping.keys.toSet();
        // normalizeKey でキーが正規化されているため小文字比較
        expect(storeKeys, contains('イオン'.toLowerCase().replaceAll(' ', '')));
      });

      test('日本語合計ラベルが含まれている', () {
        final opts = ReceiptOptions.japanese();
        final labelKeys = opts.totalLabels.mapping.keys.toSet();
        expect(labelKeys, contains('合計'));
      });

      test('tuningが日本語向けに設定されている', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.tuning.optimizerTotalTolerance, 1.0);
        expect(opts.tuning.optimizerUnrecognizedProductName, '未認識商品');
      });

      test('ドイツ語デフォルトと独立している', () {
        final ja = ReceiptOptions.japanese();
        final de = ReceiptOptions.defaults();
        expect(
          ja.tuning.optimizerTotalTolerance,
          isNot(de.tuning.optimizerTotalTolerance),
        );
        expect(
          ja.tuning.optimizerUnrecognizedProductName,
          isNot(de.tuning.optimizerUnrecognizedProductName),
        );
      });
    });

    group('kReceiptDefaultOptionsJa', () {
      test('正しいキーが含まれている', () {
        expect(kReceiptDefaultOptionsJa, contains('storeNames'));
        expect(kReceiptDefaultOptionsJa, contains('totalLabels'));
        expect(kReceiptDefaultOptionsJa, contains('ignoreKeywords'));
        expect(kReceiptDefaultOptionsJa, contains('stopKeywords'));
        expect(kReceiptDefaultOptionsJa, contains('tuning'));
      });

      test('店名にエイリアスが設定されている', () {
        final stores =
            kReceiptDefaultOptionsJa['storeNames'] as Map<String, dynamic>;
        expect(stores['AEON'], 'イオン');
        expect(stores['7-ELEVEN'], 'セブンイレブン');
        expect(stores['LAWSON'], 'ローソン');
      });
    });

    group('和暦→西暦変換', () {
      test('令和 base year = 2018', () {
        expect(ReceiptFormatter.japaneseEraMap['令和'], 2018);
      });

      test('平成 base year = 1988', () {
        expect(ReceiptFormatter.japaneseEraMap['平成'], 1988);
      });

      test('昭和 base year = 1925', () {
        expect(ReceiptFormatter.japaneseEraMap['昭和'], 1925);
      });

      test('令和7年 = 2025年', () {
        final base = ReceiptFormatter.japaneseEraMap['令和']!;
        expect(base + 7, 2025);
      });

      test('平成31年 = 2019年', () {
        final base = ReceiptFormatter.japaneseEraMap['平成']!;
        expect(base + 31, 2019);
      });

      test('昭和64年 = 1989年', () {
        final base = ReceiptFormatter.japaneseEraMap['昭和']!;
        expect(base + 64, 1989);
      });
    });

    group('DetectionMap - 日本語ラベル検出', () {
      test('日本語合計ラベルを検出する', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.totalLabels.hasMatch('合計'), isTrue);
        expect(opts.totalLabels.hasMatch('税込合計'), isTrue);
        expect(opts.totalLabels.hasMatch('小計'), isTrue);
      });

      test('日本語店名を検出する', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.storeNames.hasMatch('イオン'), isTrue);
        expect(opts.storeNames.hasMatch('LAWSON'), isTrue);
      });

      test('ストップワードを検出する', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.stopKeywords.hasMatch('お預かり'), isTrue);
        expect(opts.stopKeywords.hasMatch('現金'), isTrue);
        expect(opts.stopKeywords.hasMatch('PayPay'), isTrue);
      });

      test('無視キーワードを検出する', () {
        final opts = ReceiptOptions.japanese();
        expect(opts.ignoreKeywords.hasMatch('ポイント'), isTrue);
        expect(opts.ignoreKeywords.hasMatch('クーポン'), isTrue);
      });
    });

    group('既存機能の互換性', () {
      test('ドイツ語デフォルトオプションが正常に動作する', () {
        final opts = ReceiptOptions.defaults();
        expect(opts.storeNames.mapping, isNotEmpty);
        expect(opts.totalLabels.mapping, isNotEmpty);
      });

      test('ドイツ語店名が検出される', () {
        final opts = ReceiptOptions.defaults();
        expect(opts.storeNames.hasMatch('Aldi'), isTrue);
        expect(opts.storeNames.hasMatch('Rewe'), isTrue);
      });

      test('ドイツ語合計ラベルが検出される', () {
        final opts = ReceiptOptions.defaults();
        expect(opts.totalLabels.hasMatch('Summe'), isTrue);
        expect(opts.totalLabels.hasMatch('Total'), isTrue);
      });

      test('既存の日付パースが正常に動作する', () {
        expect(
          ReceiptFormatter.parseNumericYMD('2025-01-15'),
          DateTime.utc(2025, 1, 15),
        );
        expect(
          ReceiptFormatter.parseNumericDMY('15.01.2025'),
          DateTime.utc(2025, 1, 15),
        );
        expect(
          ReceiptFormatter.parseNameDMY('1. September 2025'),
          DateTime.utc(2025, 9, 1),
        );
      });
    });
  });
}
