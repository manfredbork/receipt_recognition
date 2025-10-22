import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('OCR from asset images (no camera)', () {
    testWidgets('REWE receipt parses total + positions (png-normalized)', (
      tester,
    ) async {
      final img = await _inputImageFromAssetAsPng(
        'integration_test/assets/rewe_01.png',
      );

      final tr = TextRecognizer(script: TextRecognitionScript.latin);
      final raw = await tr.processImage(img);
      await tr.close();
      // ignore: avoid_print
      print(raw.text);

      final rr = ReceiptRecognizer();
      try {
        final receipt = await rr.processImage(img);

        expect(receipt.totalLabel?.formattedValue, equals('SUMME'));
        expect(receipt.total?.formattedValue, equals('30.82'));
        expect(receipt.store?.formattedValue, equals('REWE'));
      } finally {
        await rr.close();
      }
    });
  });
}
