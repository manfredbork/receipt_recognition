import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/ocr/index.dart';
import 'package:receipt_recognition/src/utils/configuration/index.dart';

ReceiptOptions makeOptionsFromLists({
  List<String> food = const [],
  List<String> nonFood = const [],
  List<String> discount = const [],
  List<String> deposit = const [],
}) {
  return ReceiptOptions(
    override: <String, dynamic>{
      'storeNames': <String, String>{},
      'totalLabels': <String, String>{},
      'ignoreKeywords': <String>[],
      'stopKeywords': <String>[],
      'foodKeywords': food,
      'nonFoodKeywords': nonFood,
      'discountKeywords': discount,
      'depositKeywords': deposit,
    },
  );
}

RecognizedProduct makeProduct({
  required double price,
  required String productText,
  required String priceLineText,
  ReceiptOptions? options,
}) {
  final opts = options ?? ReceiptOptions.empty();
  final product = RecognizedProduct(
    value: productText,
    line: const ReceiptTextLine(text: ''),
    options: opts,
  );
  final priceEntity = RecognizedPrice(
    value: price,
    line: ReceiptTextLine(text: priceLineText),
  );

  final pos = RecognizedPosition(
    product: product,
    price: priceEntity,
    timestamp: DateTime.now(),
    operation: Operation.none,
  );

  product.position = pos;
  priceEntity.position = pos;

  final group = RecognizedGroup(maxGroupSize: 4);
  group.addMember(pos);

  return product;
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
      final product = RecognizedProduct(
        value: 'ITEM',
        line: const ReceiptTextLine(text: ''),
        options: ReceiptOptions.empty(),
      );
      final price = RecognizedPrice(
        value: 1.23,
        line: const ReceiptTextLine(text: '1.23'),
      );
      final pos = RecognizedPosition(
        product: product,
        price: price,
        timestamp: DateTime.now(),
        operation: Operation.none,
      );
      product.position = pos;
      price.position = pos;

      final withPosition = RecognizedReceipt.empty();
      withPosition.positions.add(pos);
      expect(withPosition.isEmpty, isFalse);

      final withTotal = RecognizedReceipt.empty();
      withTotal.total = RecognizedTotal(
        value: 9.99,
        line: const ReceiptTextLine(text: 'SUM 9.99'),
      );
      expect(withTotal.isEmpty, isFalse);
    });
  });
}
