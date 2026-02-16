import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';

void main() {
  late Map<String, dynamic> fixtures;
  late ReceiptOptions jaOptions;

  setUpAll(() async {
    final file = File('test/assets/ocr_fixtures.json');
    fixtures = jsonDecode(await file.readAsString())
        as Map<String, dynamic>;
  });

  setUp(() {
    jaOptions = ReceiptOptions.japanese();
    ReceiptTextProcessor.debugRunSynchronouslyForTests = true;
  });

  group('OCR fixture tests', () {
    test('gindaco_2026_02_08: Gindaco Sakaba receipt', () async {
      final fixture = fixtures['gindaco_2026_02_08']
          as Map<String, dynamic>;
      final text = _buildRecognizedText(fixture);
      final expected = fixture['expected'] as Map<String, dynamic>;

      final receipt =
          await ReceiptTextProcessor.processText(text, jaOptions);

      // Store name
      expect(receipt.store?.value, expected['store']);

      // Total
      expect(receipt.total?.value, expected['total']);

      // Date
      if (expected['date'] != null) {
        final parts = (expected['date'] as String).split('-');
        expect(
          receipt.purchaseDate?.value,
          DateTime.utc(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          ),
        );
      }

      // Item count
      if (expected['itemCount'] != null) {
        expect(receipt.positions.length, expected['itemCount']);
      }

      // Each item's price
      final expectedItems = expected['items'] as List<dynamic>?;
      if (expectedItems != null) {
        for (var i = 0; i < expectedItems.length; i++) {
          final item = expectedItems[i] as Map<String, dynamic>;
          expect(
            receipt.positions[i].price.value,
            item['price'],
            reason: 'position[$i] price mismatch',
          );
        }
      }

      // Debug output
      _printResult(receipt);
    });
  });
}

// ─── Fixture Loader ────────────────────────────────────────────

RecognizedText _buildRecognizedText(Map<String, dynamic> fixture) {
  final blocksJson = fixture['blocks'] as List<dynamic>;
  final blocks = <TextBlock>[];

  for (final blockJson in blocksJson) {
    final linesJson =
        (blockJson as Map<String, dynamic>)['lines'] as List<dynamic>;
    final lines = <TextLine>[];

    for (final lineJson in linesJson) {
      final l = lineJson as Map<String, dynamic>;
      final rect = l['rect'] as List<dynamic>;
      lines.add(
        ReceiptTextLine(
          text: l['text'] as String,
          boundingBox: Rect.fromLTRB(
            (rect[0] as num).toDouble(),
            (rect[1] as num).toDouble(),
            (rect[2] as num).toDouble(),
            (rect[3] as num).toDouble(),
          ),
        ),
      );
    }

    blocks.add(_FakeTextBlock(lines));
  }

  return _FakeRecognizedText(blocks);
}

void _printResult(RecognizedReceipt receipt) {
  // ignore: avoid_print
  print('--- Fixture Test Result ---');
  // ignore: avoid_print
  print('store: ${receipt.store?.value}');
  // ignore: avoid_print
  print('total: ${receipt.total?.value}');
  // ignore: avoid_print
  print('date: ${receipt.purchaseDate?.value}');
  // ignore: avoid_print
  print('positions: ${receipt.positions.length}');
  for (var i = 0; i < receipt.positions.length; i++) {
    final p = receipt.positions[i];
    // ignore: avoid_print
    print('  [$i] "${p.product.text}" = ${p.price.value}');
  }
  // ignore: avoid_print
  print('---------------------------');
}

// ─── Test Doubles ──────────────────────────────────────────────

class _FakeRecognizedText implements RecognizedText {
  @override
  final String text;

  @override
  final List<TextBlock> blocks;

  _FakeRecognizedText(this.blocks)
    : text = blocks.map((b) => b.text).join('\n');
}

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
