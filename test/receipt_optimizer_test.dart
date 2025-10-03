import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

void main() {
  late Map<String, dynamic> testReceipts;

  setUpAll(() async {
    final file = File('test/assets/test_receipts_optimizer.json');
    testReceipts = jsonDecode(await file.readAsString());
  });

  test('Haribo items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_items_same_price'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(2));
  });

  test('Milk items should be grouped together', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['very_similar_items_same_price'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(1));
  });
}
