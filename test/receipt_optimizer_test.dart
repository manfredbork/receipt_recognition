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
      testReceipts['same_texts_but_different_items_single_scan'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(receipt, test: true);

    expect(result.positions.length, equals(2));
  });

  test('Coke items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_but_different_items_single_scan'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(receipt, test: true);

    expect(result.positions.length, equals(2));
  });

  test('Haribo items should be grouped separately', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_but_different_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(receipt, test: true);

    expect(result.positions.length, equals(2));
  });

  test('Milk items should be grouped together', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['similar_texts_and_same_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(receipt, test: true);

    expect(result.positions.length, equals(1));
  });

  test('Butter items should be grouped together', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['same_texts_and_same_items_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(receipt, test: true);

    expect(result.positions.length, equals(1));
  });

  test('Purchase date is recognized and parsed correctly from JSON', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['single_item_with_purchase_date'],
    );

    expect(receipt.purchaseDate, isNotNull);
    expect(receipt.purchaseDate!.value, equals('2024-02-01'));

    final dt = receipt.purchaseDate!.parsedDateTime!;

    expect(dt.year, equals(2024));
    expect(dt.month, equals(2));
    expect(dt.day, equals(1));
  });

  test('Purchase date is preserved after optimization', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['multiple_items_with_purchase_date'],
    );
    final before = receipt.purchaseDate?.value;

    final optimizer = ReceiptOptimizer();
    final result = optimizer.optimize(receipt, test: true);

    expect(result.purchaseDate, isNotNull);
    expect(result.purchaseDate!.value, equals(before));
    expect(result.purchaseDate!.parsedDateTime, isNotNull);
  });
}
