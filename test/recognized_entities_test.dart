import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/intl.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

class MockTextLine implements TextLine {
  @override
  final String text;

  MockTextLine(this.text);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Intl.defaultLocale = 'en_US';

  group('RecognizedEntity subclasses', () {
    test('RecognizedAmount formats value correctly', () {
      final line = MockTextLine('Total: 12.34');
      final amount = RecognizedAmount(line: line, value: 12.34);

      expect(amount.formattedValue, '12.34');
    });

    test('RecognizedSum formats value with 2 decimal places', () {
      final line = MockTextLine('Total: 5');
      final sum = RecognizedSum(line: line, value: 5);

      expect(sum.formattedValue, '5.00');
    });

    test('RecognizedUnknown returns raw value', () {
      final line = MockTextLine('Some unknown line');
      final unknown = RecognizedUnknown(line: line, value: 'Some unknown line');

      expect(unknown.formattedValue, 'Some unknown line');
    });
  });

  group('RecognizedReceipt', () {
    test('Creates a receipt with all fields', () {
      final line1 = MockTextLine('Apple');
      final line2 = MockTextLine('0.99');
      final line3 = MockTextLine('Total');
      final position = RecognizedPosition(
        product: RecognizedProduct(line: line1, value: 'Apple'),
        price: RecognizedPrice(line: line2, value: 0.99),
        timestamp: DateTime.now(),
        group: PositionGroup.empty(),
        operation: Operation.added,
      );

      final receipt = RecognizedReceipt(
        positions: [position],
        timestamp: DateTime.now(),
        sumLabel: RecognizedSumLabel(line: line3, value: 'Total'),
        sum: RecognizedSum(line: line2, value: 0.99),
        company: RecognizedCompany(line: line1, value: 'Store Inc.'),
      );

      expect(receipt.positions.length, 1);
      expect(receipt.sumLabel!.value, 'Total');
      expect(receipt.sum!.value, 0.99);
      expect(receipt.company!.value, 'Store Inc.');
    });

    test('Allows null sum label, sum and company', () {
      final line = MockTextLine('Banana');
      final position = RecognizedPosition(
        product: RecognizedProduct(line: line, value: 'Banana'),
        price: RecognizedPrice(line: line, value: 1.49),
        timestamp: DateTime.now(),
        group: PositionGroup.empty(),
        operation: Operation.added,
      );

      final receipt = RecognizedReceipt(
        positions: [position],
        timestamp: position.timestamp,
      );

      expect(receipt.positions.length, 1);
      expect(receipt.positions.first.product.value, 'Banana');
      expect(receipt.positions.first.price.formattedValue, '1.49');
      expect(receipt.calculatedSum.formattedValue, '1.49');
      expect(receipt.sumLabel, isNull);
      expect(receipt.sum, isNull);
      expect(receipt.company, isNull);
    });
  });
}
