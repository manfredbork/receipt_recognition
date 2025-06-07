import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  late Map<String, dynamic> testReceipts;

  setUpAll(() async {
    final file = File('test/assets/test_receipts_with_timestamps.json');
    testReceipts = jsonDecode(await file.readAsString());
  });

  test('Haribo items should be grouped together with low threshold', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['too_few_positions'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 2, confidenceThreshold: 60);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(1));
  });

  test('Milk items should be separated with high threshold', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['too_many_positions'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 2, confidenceThreshold: 90);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(2));
  });
}
