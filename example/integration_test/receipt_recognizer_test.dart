import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:integration_test/integration_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

Future<File> _assetToTemp(String key) async {
  final data = await rootBundle.load(key);
  final dir = await Directory.systemTemp.createTemp('mlkit_');
  final file = File('${dir.path}/${key.split('/').last}');
  await file.writeAsBytes(
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    flush: true,
  );
  return file;
}

Future<InputImage> inputImageFromAssetUprightPath(String assetKey) async {
  final f = await _assetToTemp(assetKey);
  final fixed = await FlutterExifRotation.rotateImage(path: f.path);
  return InputImage.fromFilePath(fixed.path);
}

Future<RecognizedReceipt> _detectReceiptFromAsset(
  String assetPath, {
  ReceiptOptions? options,
}) async {
  final inputImage = await inputImageFromAssetUprightPath(assetPath);
  final receiptRecognizer = ReceiptRecognizer(options: options);
  final receipt = receiptRecognizer.processImage(inputImage);
  await receiptRecognizer.close();
  return receipt;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('OCR from asset images (no camera)', () {
    testWidgets('Edeka receipt parses total + positions', (tester) async {
      final r = await _detectReceiptFromAsset(
        'integration_test/assets/rewe_03.jpg',
      );
      expect(r.total, isNotNull, reason: 'Should detect total');
      expect(
        r.positions.length,
        greaterThan(0),
        reason: 'Should parse at least one line item',
      );
      expect(r.store?.formattedValue, equals('EDEKA'));
    });
  });
}
