import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

ReceiptOptions makeOptionsFromLists({List<String> groups = const []}) {
  return ReceiptOptions(
    override: <String, dynamic>{'allowedProductGroups': groups},
  );
}

RecognizedPosition makePosition({
  required double price,
  required String productText,
  required String priceLineText,
  int? unitQuantity,
  double? unitPrice,
  ReceiptOptions? options,
}) {
  final opts = options ?? ReceiptOptions.empty();
  final product = RecognizedProduct(
    value: productText,
    line: ReceiptTextLine(text: productText),
    options: opts,
  );
  final prc = RecognizedPrice(
    value: price,
    line: ReceiptTextLine(text: priceLineText),
  );
  final unit = RecognizedUnit.fromNumbers(
    unitQuantity ?? 1,
    unitPrice ?? price,
    ReceiptTextLine(),
  );
  final pos = RecognizedPosition(
    product: product,
    price: prc,
    timestamp: DateTime.now(),
    operation: Operation.none,
    unit: unit,
  );

  product.position = pos;
  prc.position = pos;

  final group = RecognizedGroup(maxGroupSize: 4);
  group.addMember(pos);

  return pos;
}

void main() {
  group('RecognizedReceipt.isEmpty', () {
    test('isEmpty == true when there are no positions and no total', () {
      final r = RecognizedReceipt.empty();
      expect(r.positions, isEmpty);
      expect(r.total, isNull);
      expect(r.isEmpty, isTrue);
    });

    test('isEmpty == false when there is at least one position or a total', () {
      final withPosition = RecognizedReceipt.empty();
      final pos = makePosition(
        price: 1.23,
        productText: 'ITEM',
        priceLineText: '1.23',
      );
      withPosition.positions.add(pos);
      expect(withPosition.isEmpty, isFalse);

      final withTotal = RecognizedReceipt.empty();
      withTotal.total = RecognizedTotal(
        value: 9.99,
        line: const ReceiptTextLine(text: '9.99'),
      );
      expect(withTotal.isEmpty, isFalse);
    });

    test('one position with product group', () {
      final withPosition = RecognizedReceipt.empty();
      final pos = makePosition(
        price: 1.23,
        productText: 'ITEM',
        priceLineText: '1.23 A *',
      );
      withPosition.positions.add(pos);
      expect(withPosition.isEmpty, isFalse);
      expect(withPosition.positions.first.product.productGroup, equals('A'));
    });

    test('one position with unit quantity and price', () {
      final withPosition = RecognizedReceipt.empty();
      final pos = makePosition(
        price: 2.00,
        productText: 'ITEM',
        priceLineText: '2.00',
        unitQuantity: 2,
        unitPrice: 1.00,
      );
      withPosition.positions.add(pos);
      final unit = withPosition.positions.first.product.unit;

      expect(withPosition.isEmpty, isFalse);
      expect(unit.quantity.value, equals(2));
      expect(unit.price.value, equals(1.00));
    });
  });
}
