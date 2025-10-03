import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Returns a RecognizedReceipt from json[key], or null if missing.
RecognizedReceipt? _receiptFrom(Map<String, dynamic> json, String key) {
  final node = json[key];
  if (node == null) return null;
  return RecognizedReceipt.fromJson(node);
}

/// Close in cents (±1¢ default).
bool _close(double a, double b, {int cents = 1}) =>
    ((a - b).abs() <= cents / 100.0);

void main() {
  late Map<String, dynamic> fixtures;

  setUpAll(() async {
    final file = File('test/assets/test_receipts_outlier_remover.json');
    fixtures = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  });

  test('allows at least one deletion for small receipts (n=3)', () {
    final receipt = _receiptFrom(fixtures, 'outlier_single')!;
    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);
    expect(receipt.positions.length, 2);
  });

  test(
    'json/outlier_single: removes one duplicate/misread price to match sum',
    () {
      final receipt = _receiptFrom(fixtures, 'outlier_single');
      if (receipt == null) {
        return;
      }

      final detected = receipt.sum!.value.toDouble();
      ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);
      final left = receipt.calculatedSum.value.toDouble();
      expect(
        _close(left, detected),
        isTrue,
        reason:
            'Remaining positions should match detected sum within ±1¢ (got $left vs $detected).',
      );
    },
  );

  test('json/outlier_pair: removes two junk prices to match sum', () {
    final receipt = _receiptFrom(fixtures, 'outlier_pair');
    if (receipt == null) {
      return;
    }

    final detected = receipt.sum!.value.toDouble();
    final beforeLen = receipt.positions.length;

    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);

    final afterLen = receipt.positions.length;
    final left = receipt.calculatedSum.value.toDouble();

    expect(
      _close(left, detected),
      isTrue,
      reason:
          'Remaining positions should match detected sum within ±1¢ (got $left vs $detected).',
    );
    expect(afterLen <= beforeLen, isTrue);
  });

  test('json/outlier_summe: removes a misparsed SUMME/metadata line', () {
    final receipt = _receiptFrom(fixtures, 'outlier_summe');
    if (receipt == null) {
      return;
    }

    final detected = receipt.sum!.value.toDouble();

    final hadSumme = receipt.positions.any(
      (p) => p.product.value.toString().toLowerCase().contains('summe'),
    );
    expect(hadSumme, isTrue, reason: 'Fixture must include a SUMME line.');

    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);

    final hasSummeNow = receipt.positions.any(
      (p) => p.product.value.toString().toLowerCase().contains('summe'),
    );
    expect(
      hasSummeNow,
      isFalse,
      reason: 'SUMME line should have been removed as outlier.',
    );

    final left = receipt.calculatedSum.value.toDouble();
    expect(_close(left, detected), isTrue);
  });

  test('json/outlier_no_solution: unchanged when no subset fits tolerance', () {
    final receipt = _receiptFrom(fixtures, 'outlier_no_solution');
    if (receipt == null) {
      return;
    }

    final before = receipt.positions.map((p) => p.product.value).toList();

    ReceiptOutlierRemover.removeOutliersToMatchSum(receipt);

    final after = receipt.positions.map((p) => p.product.value).toList();
    expect(
      after,
      before,
      reason:
          'When no subset matches Δ within tolerance, receipt should remain unchanged.',
    );
  });
}
