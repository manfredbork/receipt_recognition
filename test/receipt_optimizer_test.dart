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

  test('Deposit items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['same_texts_but_different_items_one_scan'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(2));
  });

  test('Coke items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_but_different_items_one_scan'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(2));
  });

  test('Haribo items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_but_different_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(2));
  });

  test('Milk items should be grouped together', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_and_same_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(1));
  });

  test('Butter items should be grouped together', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['same_texts_and_same_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer(maxCacheSize: 1);

    final result = optimizer.optimize(receipt, force: true);

    expect(result.positions.length, equals(1));
  });
}
