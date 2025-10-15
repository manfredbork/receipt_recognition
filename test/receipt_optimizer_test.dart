import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/optimizer/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

void main() {
  late Map<String, dynamic> testReceipts;

  setUpAll(() async {
    final file = File('test/assets/test_receipts_optimizer.json');
    testReceipts = jsonDecode(await file.readAsString());
  });

  test('Three `Sausage` items should be grouped in two groups', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['three_items_same_text_two_groups_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(2));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Banana` items should be grouped in two groups', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_same_text_same_price_two_groups_single_scan'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(2));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Deposit` items should be grouped in two groups', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_same_text_two_groups_single_scan'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(2));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Coke` items should be grouped in two groups', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_similar_text_two_groups_single_scan'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(2));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Haribo` items should be grouped in two groups', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_same_text_two_groups_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(2));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Milk` items should be grouped in same group', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_similar_text_single_group_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(1));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Two `Butter` items should be grouped in same group', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['two_items_same_text_single_group_two_scans'],
    );
    final optimizer = ReceiptOptimizer();

    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.positions.length, equals(1));
    expect(result.sum?.value, result.calculatedSum.value);
  });

  test('Purchase date is recognized and parsed correctly', () {
    final receipt = RecognizedReceipt.fromJson(
      testReceipts['single_item_purchase_date'],
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
      testReceipts['two_items_purchase_date'],
    );
    final before = receipt.purchaseDate?.value;

    final optimizer = ReceiptOptimizer();
    final result = optimizer.optimize(
      receipt,
      ReceiptOptions.defaults(),
      test: true,
    );

    expect(result.purchaseDate, isNotNull);
    expect(result.purchaseDate!.value, equals(before));
    expect(result.purchaseDate!.parsedDateTime, isNotNull);
  });
}
