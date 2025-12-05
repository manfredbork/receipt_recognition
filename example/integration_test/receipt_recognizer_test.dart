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
  InputImage img = await _inputImageFromAssetAsPng(
    'integration_test/assets/$file',
  );
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
        final receipt = await _processImage('01-rewe-de.png');

        expect(receipt.store?.formattedValue, equals('REWE'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('30.82'));
        expect(receipt.total?.formattedValue, equals('30.82'));

        final items = receipt.positions;

        expect(items[0].product.formattedValue, equals('BEDIENUNGSTHEKE'));
        expect(items[0].price.value, equals(7.77));
        expect(items[1].product.formattedValue, equals('HERINGSFILET'));
        expect(items[1].price.value, equals(3.98));
        expect(items[1].product.unit.quantity.value, equals(2));
        expect(items[1].product.unit.price.value, equals(1.99));
        expect(items[2].product.formattedValue, equals('KARTOFFELN'));
        expect(items[2].price.value, equals(1.69));
        expect(items[3].product.formattedValue, equals('BIO WEIDEMILCH'));
        expect(items[3].price.value, equals(2.70));
        expect(items[4].product.formattedValue, equals('ESL MILCH 3.5%'));
        expect(items[4].price.value, equals(1.09));
        expect(items[5].product.formattedValue, equals('ARLA MILCH 3,8%'));
        expect(items[5].price.value, equals(3.58));
        expect(items[5].product.unit.quantity.value, equals(2));
        expect(items[5].product.unit.price.value, equals(1.79));
        expect(items[6].product.formattedValue, equals('VANILLE-SOSSE'));
        expect(items[6].price.value, equals(2.58));
        expect(items[6].product.unit.quantity.value, equals(2));
        expect(items[6].product.unit.price.value, equals(1.29));
        expect(items[7].product.formattedValue, equals('GOETTERSP. WALD'));
        expect(items[7].price.value, equals(1.29));
        expect(items[8].product.formattedValue, equals('GOETTERSP. HIMB.'));
        expect(items[8].price.value, equals(1.29));
        expect(items[9].product.formattedValue, equals('CLASSIC 2IN1'));
        expect(items[9].price.value, equals(2.79));
        expect(items[10].product.formattedValue, equals('CITRUSFRISCHE'));
        expect(items[10].price.value, equals(3.18));
        expect(items[10].product.unit.quantity.value, equals(2));
        expect(items[10].product.unit.price.value, equals(1.59));
        expect(items[11].product.formattedValue, equals('SH ANT-SCHUPPEN'));
        expect(items[11].price.value, equals(1.59));
        expect(items[12].product.formattedValue, equals('OBLATENLEBKUCHEN'));
        expect(items[12].price.value, equals(2.49));
        expect(items[13].product.formattedValue, equals('LEERG. EW E. SI'));
        expect(items[13].price.value, equals(-0.25));
        expect(items[14].product.formattedValue, equals('LEERG. MM V. ST'));
        expect(items[14].price.value, equals(-1.95));
        expect(items[14].product.unit.quantity.value, equals(13));
        expect(items[14].product.unit.price.value, equals(-0.15));
        expect(items[15].product.formattedValue, equals('LEERG. MW V. ST'));
        expect(items[15].price.value, equals(-1.50));
        expect(items[16].product.formattedValue, equals('LEERGUT EINWEG'));
        expect(items[16].price.value, equals(-1.50));
        expect(items[16].product.unit.quantity.value, equals(6));
        expect(items[16].product.unit.price.value, equals(-0.25));
        expect(items[16].product.productGroup, equals('A'));
      },
    );

    testWidgets(
      'EDEKA receipt check store + total + positions length + single position + unit',
      (tester) async {
        final receipt = await _processImage('02-edeka-de.png');

        expect(receipt.store?.formattedValue, equals('EDEKA'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('27.63'));
        expect(receipt.total?.formattedValue, equals('27.63'));

        final items = receipt.positions;

        expect(items.length, equals(11));
        expect(items[6].product.text, equals('Gurken mini'));
        expect(items[6].price.formattedValue, equals('1.78'));
        expect(items[6].product.unit.quantity.value, equals(2));
        expect(items[6].product.unit.price.value, equals(0.89));
      },
    );

    testWidgets(
      'LIDL receipt check store + total + purchase date + positions length + single position + unit',
      (tester) async {
        final receipt = await _processImage('03-lidl-de.png');

        expect(receipt.totalLabel?.formattedValue, equals('ZU ZAHLEN'));
        expect(receipt.calculatedTotal.formattedValue, equals('14.24'));
        expect(receipt.total?.formattedValue, equals('14.24'));
        expect(
          receipt.purchaseDate?.formattedValue,
          equals('2025-10-21T00:00:00.000Z'),
        );

        final items = receipt.positions;

        expect(items.length, equals(5));
        expect(items[3].product.text, equals('Müller Mül lerm.Erdb.'));
        expect(items[3].price.value, equals(1.38));
        expect(items[3].product.unit.quantity.value, equals(2));
        expect(items[3].product.unit.price.value, equals(0.69));
      },
    );

    testWidgets(
      'ALDI receipt check store + total + purchase date + positions length + single position',
      (tester) async {
        final receipt = await _processImage('04-aldi-de.png');

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

    testWidgets('REWE receipt special checks related to deposit positions', (
      tester,
    ) async {
      final receipt = await _processImage('05-rewe-de.png');

      expect(receipt.store?.formattedValue, equals('REWE'));
      expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
      expect(receipt.calculatedTotal.formattedValue, equals('32.68'));
      expect(receipt.total?.formattedValue, equals('32.68'));

      final items = receipt.positions;

      expect(items.length, equals(22));
      expect(items[8].product.text, equals('PFAND 0,25 EURO'));
      expect(items[8].price.value, equals(0.25));
      expect(items[10].product.text, equals('PFAND 0,25 EURO'));
      expect(items[10].price.value, equals(0.25));
    });

    testWidgets(
      'EDEKA check store + total + positions length + positions + units',
      (tester) async {
        final receipt = await _processImage('06-edeka-de.png');

        expect(receipt.store?.formattedValue, equals('EDEKA'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('12.34'));
        expect(receipt.total?.formattedValue, equals('12.34'));

        final items = receipt.positions;

        expect(items.length, equals(8));
        expect(items[0].product.text, equals('Bio E.Vollmil'));
        expect(items[0].price.value, equals(2.78));
        expect(items[0].product.unit.quantity.value, equals(2));
        expect(items[0].product.unit.price.value, equals(1.39));
        expect(items[1].product.text, equals('Rama Original'));
        expect(items[1].price.value, equals(3.33));
        expect(items[1].product.unit.quantity.value, equals(3));
        expect(items[1].product.unit.price.value, equals(1.11));
        expect(items[2].product.text, equals('Hom.Paprika Sauce'));
        expect(items[2].price.value, equals(1.29));
        expect(items[3].product.text, equals('Hom.Currywur.Sauce'));
        expect(items[3].price.value, equals(1.29));
        expect(items[4].product.text, equals('Ahoj Brausebrocken'));
        expect(items[4].price.value, equals(0.89));
        expect(items[5].product.text, equals('Detk.Mousse'));
        expect(items[5].price.value, equals(0.69));
        expect(items[6].product.text, equals('Detker Mom.Mousse'));
        expect(items[6].price.value, equals(0.69));
        expect(items[7].product.text, equals('Detk.Mousse a'));
        expect(items[7].price.value, equals(1.38));
        expect(items[7].product.unit.quantity.value, equals(2));
        expect(items[7].product.unit.price.value, equals(0.69));
      },
    );

    tearDown(() {
      ReceiptTextProcessor.debugRunSynchronouslyForTests = false;
    });
  });
}
