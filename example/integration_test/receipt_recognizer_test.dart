import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

Future<File> _assetToUprightPng(String assetKey) async {
  final data = await rootBundle.load(assetKey);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  final fi = await codec.getNextFrame();
  final uiImage = fi.image;
  final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
  final Uint8List pngBytes = byteData!.buffer.asUint8List();
  final dir = await Directory.systemTemp.createTemp('ocr_png_');
  final file = File('${dir.path}/${assetKey.split('/').last}.png');
  await file.writeAsBytes(pngBytes, flush: true);
  return file;
}

Future<InputImage> _inputImageFromAssetAsPng(String assetKey) async {
  final pngFile = await _assetToUprightPng(assetKey);
  return InputImage.fromFilePath(pngFile.path);
}

Future<RecognizedReceipt> _processImage(String file) async {
  final img = await _inputImageFromAssetAsPng('integration_test/assets/$file');
  final rr = ReceiptRecognizer(singleScan: true);
  try {
    final receipt = await rr.processImage(img);
    debugPrint(
      '\n############### Integration test where receipt is recognized from image "$file" ###############',
    );
    ReceiptLogger.logReceipt(receipt);
    return receipt;
  } finally {
    await rr.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReceiptTextProcessor.debugRunSynchronouslyForTests = true;
  });

  group('OCR from asset images (no camera)', () {
    testWidgets(
      'REWE receipt check store + total + positions + units + group',
      (tester) async {
        final receipt = await _processImage('rewe.png');

        expect(receipt.store?.formattedValue, equals('REWE'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('30.82'));
        expect(receipt.total?.formattedValue, equals('30.82'));

        final items = receipt.positions;

        expect(items[0].product.formattedValue, equals('BEDIENUNGSTHEKE'));
        expect(items[0].price.formattedValue, equals('7.77'));
        expect(items[1].product.formattedValue, equals('HERINGSFILET'));
        expect(items[1].price.formattedValue, equals('3.98'));
        expect(items[2].product.formattedValue, equals('KARTOFFELN'));
        expect(items[2].price.formattedValue, equals('1.69'));
        expect(items[3].product.formattedValue, equals('BIO WEIDEMILCH'));
        expect(items[3].price.formattedValue, equals('2.70'));
        expect(items[4].product.formattedValue, equals('ESL MILCH 3.5%'));
        expect(items[4].price.formattedValue, equals('1.09'));
        expect(items[5].product.formattedValue, equals('ARLA MILCH 3,8%'));
        expect(items[5].price.formattedValue, equals('3.58'));
        expect(items[6].product.formattedValue, equals('VANILLE-SOSSE'));
        expect(items[6].price.formattedValue, equals('2.58'));
        expect(items[7].product.formattedValue, equals('GOETTERSP. WALD'));
        expect(items[7].price.formattedValue, equals('1.29'));
        expect(items[8].product.formattedValue, equals('GOETTERSP. HIMB.'));
        expect(items[8].price.formattedValue, equals('1.29'));
        expect(items[9].product.formattedValue, equals('CLASSIC 2IN1'));
        expect(items[9].price.formattedValue, equals('2.79'));
        expect(items[10].product.formattedValue, equals('CITRUSFRISCHE'));
        expect(items[10].price.formattedValue, equals('3.18'));
        expect(items[11].product.formattedValue, equals('SH ANT-SCHUPPEN'));
        expect(items[11].price.formattedValue, equals('1.59'));
        expect(items[12].product.formattedValue, equals('OBLATENLEBKUCHEN'));
        expect(items[12].price.formattedValue, equals('2.49'));
        expect(items[13].product.formattedValue, equals('LEERG. EW E. SI'));
        expect(items[13].price.formattedValue, equals('-0.25'));
        expect(items[14].product.formattedValue, equals('LEERG. MM V. ST'));
        expect(items[14].price.formattedValue, equals('-1.95'));
        expect(items[15].product.formattedValue, equals('LEERG. MW V. ST'));
        expect(items[15].price.formattedValue, equals('-1.50'));
        expect(items[16].product.formattedValue, equals('LEERGUT EINWEG'));
        expect(items[16].price.formattedValue, equals('-1.50'));
        expect(items[16].product.unit.quantity.value, equals(6));
        expect(items[16].product.unit.price.value, equals(-0.25));
        expect(items[16].product.productGroup, equals('A'));
      },
    );

    testWidgets(
      'EDEKA receipt check store + total + positions length + single position',
      (tester) async {
        final receipt = await _processImage('edeka.png');

        expect(receipt.store?.formattedValue, equals('EDEKA'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('27.63'));
        expect(receipt.total?.formattedValue, equals('27.63'));

        final items = receipt.positions;

        expect(items.length, equals(11));
        expect(items[6].product.text, equals('Gurken mini'));
      },
    );

    testWidgets(
      'LIDL receipt check total + purchase date + positions length + single position',
      (tester) async {
        final receipt = await _processImage('lidl.png');

        expect(receipt.totalLabel?.formattedValue, equals('ZU ZAHLEN'));
        expect(receipt.calculatedTotal.formattedValue, equals('14.24'));
        expect(receipt.total?.formattedValue, equals('14.24'));
        expect(
          receipt.purchaseDate?.formattedValue,
          equals('2025-10-21T00:00:00.000Z'),
        );

        final items = receipt.positions;

        expect(items.length, equals(5));
        expect(items[4].product.text, equals('Weihenstephan Tafel.'));
        expect(items[4].price.value, equals(1.99));
      },
    );

    testWidgets(
      'ALDI receipt check store + total + purchase date + positions length + single position',
      (tester) async {
        final receipt = await _processImage('aldi.png');

        expect(receipt.store?.formattedValue, equals('ALDI'));
        expect(receipt.totalLabel?.formattedValue, equals('ZU ZAHLEN'));
        expect(receipt.calculatedTotal.formattedValue, equals('11.86'));
        expect(receipt.total?.formattedValue, equals('11.86'));
        expect(
          receipt.purchaseDate?.formattedValue,
          equals('2025-11-08T00:00:00.000Z'),
        );

        final items = receipt.positions;

        expect(items.length, equals(4));
        expect(items[3].product.text, equals('DT. MARKENBUTTER'));
        expect(items[3].price.value, equals(1.39));
      },
    );

    tearDown(() {
      ReceiptTextProcessor.debugRunSynchronouslyForTests = false;
    });
  });
}
