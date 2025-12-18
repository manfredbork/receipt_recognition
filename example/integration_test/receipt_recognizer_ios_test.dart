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

Future<RecognizedReceipt> _processImage(String fileName) async {
  InputImage img = await _inputImageFromAssetAsPng(
    'integration_test/assets/$fileName',
  );
  final rr = ReceiptRecognizer(
    singleScan: true,
    script: _extractScriptLanguage(fileName),
  );
  try {
    final receipt = await rr.processImage(img);
    debugPrint(
      '\n############### Integration test where receipt is recognized from image "$fileName" ###############',
    );
    ReceiptLogger.logReceipt(receipt);
    return receipt;
  } finally {
    await rr.close();
  }
}

TextRecognitionScript _extractScriptLanguage(String fileName) {
  final langCode = _extractLangCode(fileName);
  if (langCode == 'zh') {
    return TextRecognitionScript.chinese;
  } else if (langCode == 'ja') {
    return TextRecognitionScript.japanese;
  } else if (langCode == 'ko') {
    return TextRecognitionScript.korean;
  }
  return TextRecognitionScript.latin;
}

String? _extractLangCode(String fileName) {
  final regex = RegExp(r'-([a-z]{2})\.[^.]+$');
  final match = regex.firstMatch(fileName);
  return match?.group(1);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    ReceiptTextProcessor.debugRunSynchronouslyForTests = true;
  });

  group('OCR from asset images (no camera)', () {
    testWidgets(
      'ALDI check store + total + purchase date + positions length + single position',
      (tester) async {
        final receipt = await _processImage('01-aldi-de.png');

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

    testWidgets(
      'EDEKA check store + total + positions length + single position + unit',
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
      'EDEKA #2 check store + total + positions length + positions + units',
      (tester) async {
        final receipt = await _processImage('03-edeka-de.png');

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

    testWidgets('REWE check store + total + positions + units + group', (
      tester,
    ) async {
      final receipt = await _processImage('04-rewe-de.png');

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
    });

    testWidgets('REWE #2 check properties related to deposit positions', (
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
      'LIDL check store + total + purchase date + positions length + single position + unit',
      (tester) async {
        final receipt = await _processImage('06-lidl-de.png');

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
      'KAUFLAND check store + total + positions length + positions + units',
      (tester) async {
        final receipt = await _processImage('07-kaufland-de.png');

        expect(receipt.store?.formattedValue, equals('KAUFLAND'));
        expect(receipt.totalLabel?.formattedValue, equals('SUM'));
        expect(receipt.calculatedTotal.formattedValue, equals('76.92'));
        expect(receipt.total?.formattedValue, equals('76.92'));

        final items = receipt.positions;

        expect(items.length, equals(21));

        expect(items[0].product.text, equals('Feldsalat 150g'));
        expect(items[0].price.value, equals(0.79));
        expect(items[0].product.unit.quantity.value, equals(1));
        expect(items[0].product.unit.price.value, equals(0.79));
        expect(items[1].product.text, equals('Hä.Cordon Bleu XXL'));
        expect(items[1].price.value, equals(6.49));
        expect(items[1].product.unit.quantity.value, equals(1));
        expect(items[1].product.unit.price.value, equals(6.49));
        expect(items[2].product.text, equals('Nivea Creme Soft'));
        expect(items[2].price.value, equals(2.99));
        expect(items[2].product.unit.quantity.value, equals(1));
        expect(items[2].product.unit.price.value, equals(2.99));
        expect(items[3].product.text, equals('Kinder Schoko Bons'));
        expect(items[3].price.value, equals(2.79));
        expect(items[3].product.unit.quantity.value, equals(1));
        expect(items[3].product.unit.price.value, equals(2.79));
        expect(items[4].product.text, equals('Kiwi gelb'));
        expect(items[4].price.value, equals(1.58));
        expect(items[4].product.unit.quantity.value, equals(2));
        expect(items[4].product.unit.price.value, equals(0.79));
        expect(items[5].product.text, equals('Bauernschinken'));
        expect(items[5].price.value, equals(4.99));
        expect(items[6].product.text, equals('Entenbrust geräuch'));
        expect(items[6].price.value, equals(1.99));
        expect(items[7].product.text, equals('Spianata Romana'));
        expect(items[7].price.value, equals(1.99));
        expect(items[8].product.text, equals('0ld Sp Geschenkset'));
        expect(items[8].price.value, equals(8.95));
        expect(items[9].product.text, equals('Mü.Kalinka Kefir'));
        expect(items[9].price.value, equals(2.58));
        expect(items[9].product.unit.quantity.value, equals(2));
        expect(items[9].product.unit.price.value, equals(1.29));
        expect(items[10].product.text, equals('Pfandart ikel'));
        expect(items[10].price.value, equals(0.50));
        expect(items[10].product.unit.quantity.value, equals(2));
        expect(items[10].product.unit.price.value, equals(0.25));
        expect(items[11].product.text, equals('Lindt Pralines'));
        expect(items[11].price.value, equals(9.98));
        expect(items[11].product.unit.quantity.value, equals(2));
        expect(items[11].product.unit.price.value, equals(4.99));
        expect(items[12].product.text, equals('Meg.FeineSüssrahm'));
        expect(items[12].price.value, equals(5.98));
        expect(items[12].product.unit.quantity.value, equals(2));
        expect(items[12].product.unit.price.value, equals(2.99));
        expect(items[13].product.text, equals('Artikelrabatt'));
        expect(items[13].price.value, equals(-3.00));
        expect(items[13].product.unit.quantity.value, equals(1));
        expect(items[13].product.unit.price.value, equals(-3.00));
        expect(items[14].product.text, equals('Lindt Hochfein'));
        expect(items[14].price.value, equals(19.98));
        expect(items[14].product.unit.quantity.value, equals(2));
        expect(items[14].product.unit.price.value, equals(9.99));
        expect(items[15].product.text, equals('KLC.Burgerbrötchen'));
        expect(items[15].price.value, equals(0.99));
        expect(items[16].product.text, equals('Rote Bete Scheiben'));
        expect(items[16].price.value, equals(1.09));
        expect(items[17].product.text, equals('Schw.Sauce Schoko'));
        expect(items[17].price.value, equals(1.59));
        expect(items[18].product.text, equals('Schw.Sauce Caramel'));
        expect(items[18].price.value, equals(1.59));
        expect(items[19].product.text, equals('Schw.Sauce Erdbeer'));
        expect(items[19].price.value, equals(1.59));
        expect(items[20].product.text, equals('K-Bio Gurken'));
        expect(items[20].price.value, equals(1.49));
        expect(items[20].product.unit.quantity.value, equals(1));
        expect(items[20].product.unit.price.value, equals(1.49));
      },
    );

    testWidgets(
      'KAUFLAND #2 check store + total + positions length + positions + units',
      (tester) async {
        final receipt = await _processImage('08-kaufland-de.png');

        expect(receipt.store?.formattedValue, equals('KAUFLAND'));
        expect(receipt.totalLabel?.formattedValue, equals('SUM'));
        expect(receipt.calculatedTotal.formattedValue, equals('45.34'));
        expect(receipt.total?.formattedValue, equals('45.34'));

        final items = receipt.positions;

        expect(items.length, equals(11));
        expect(items[0].product.text, equals('Kinder We ihn.-mann'));
        expect(items[0].price.value, equals(5.98));
        expect(items[0].product.unit.quantity.value, equals(2));
        expect(items[0].product.unit.price.value, equals(2.99));
        expect(items[1].product.text, equals('Zigaretten'));
        expect(items[1].price.value, equals(6.20));
        expect(items[1].product.unit.quantity.value, equals(2));
        expect(items[1].product.unit.price.value, equals(3.10));
        expect(items[2].product.text, equals('Kinder Weihn.-manrn'));
        expect(items[2].price.value, equals(1.99));
        expect(items[3].product.text, equals('K.Salami Pur Porc'));
        expect(items[3].price.value, equals(2.99));
        expect(items[4].product.text, equals('KLC. Ede lsalami'));
        expect(items[4].price.value, equals(5.99));
        expect(items[5].product.text, equals('Nesquik Snack'));
        expect(items[5].price.value, equals(2.69));
        expect(items[6].product.text, equals('Osterl.Grütze'));
        expect(items[6].price.value, equals(1.96));
        expect(items[6].product.unit.quantity.value, equals(4));
        expect(items[6].product.unit.price.value, equals(0.49));
        expect(items[7].product.text, equals('Markknochen'));
        expect(items[7].price.value, equals(2.03));
        expect(items[8].product.text, equals('Markknochen'));
        expect(items[8].price.value, equals(1.56));
        expect(items[9].product.text, equals('Bifi Roll'));
        expect(items[9].price.value, equals(1.99));
        expect(items[10].product.text, equals('Philips LED Kerze'));
        expect(items[10].price.value, equals(11.96));
        expect(items[10].product.unit.quantity.value, equals(4));
        expect(items[10].product.unit.price.value, equals(2.99));
      },
    );

    testWidgets(
      'DM check store + total + purchase date + positions length + positions',
      (tester) async {
        final receipt = await _processImage('09-dm-de.png');

        expect(receipt.store?.formattedValue, equals('DM'));
        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.calculatedTotal.formattedValue, equals('33.80'));
        expect(receipt.total?.formattedValue, equals('33.80'));
        expect(
          receipt.purchaseDate?.formattedValue,
          equals('2025-12-12T00:00:00.000Z'),
        );

        final items = receipt.positions;

        expect(items.length, equals(13));
        expect(items[0].product.text, equals('Prof .Tücher Mikrofeinf'));
        expect(items[0].price.value, equals(5.50));
        expect(items[1].product.text, equals('Profissimo Tortenunter lagen'));
        expect(items[1].price.value, equals(0.95));
        expect(items[2].product.text, equals('I-eukal Gum Euka 90g'));
        expect(items[2].price.value, equals(1.85));
        expect(items[3].product.text, equals('Em-eukal Hustenmischung'));
        expect(items[3].price.value, equals(1.85));
        expect(items[4].product.text, equals('Kamill Hand&Nage lcreme Balsam'));
        expect(items[4].price.value, equals(1.55));
        expect(items[5].product.text, equals('Balea Fußbutter Pfirsich'));
        expect(items[5].price.value, equals(2.45));
        expect(items[6].product.text, equals('Balea Fußcreme Totes Meer'));
        expect(items[6].price.value, equals(2.45));
        expect(items[7].product.text, equals('Neutrogena Fuß Fußcreme trock'));
        expect(items[7].price.value, equals(3.95));
        expect(items[8].product.text, equals('Balea FuB Vitalbad'));
        expect(items[8].price.value, equals(1.65));
        expect(items[9].product.text, equals('Balea Fuß Bimsschwamn 1St'));
        expect(items[9].price.value, equals(0.95));
        expect(items[10].product.text, equals('Balea Hornhaut Keramikfeile'));
        expect(items[10].price.value, equals(3.45));
        expect(items[11].product.text, equals('Credo Fußfeile+Feilenbl.'));
        expect(items[11].price.value, equals(2.95));
        expect(items[12].product.text, equals('Girlande 88cm Zapfen 2f'));
        expect(items[12].price.value, equals(4.25));
      },
    );

    testWidgets(
      'ALDI #2 check store + total + purchase date + positions length + units',
      (tester) async {
        final receipt = await _processImage('10-aldi-de.png');

        expect(receipt.store?.formattedValue, equals('ALDI'));
        expect(receipt.totalLabel?.formattedValue, equals('ZU ZAHLEN'));
        expect(receipt.calculatedTotal.formattedValue, equals('34.05'));
        expect(receipt.total?.formattedValue, equals('34.05'));
        expect(
          receipt.purchaseDate?.formattedValue,
          equals('2025-12-18T00:00:00.000Z'),
        );

        final items = receipt.positions;

        expect(items.length, equals(19));
        expect(items[0].product.unit.quantity.value, equals(6));
        expect(items[0].product.unit.price.value, equals(0.99));
      },
    );

    tearDown(() {
      ReceiptTextProcessor.debugRunSynchronouslyForTests = false;
    });
  });
}
