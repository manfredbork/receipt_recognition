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

/// Wire up a minimal product/price/position/group so postfix extraction works.
/// Supply a `priceLineText` like "3.49 FOODX" so the group can derive postfix "FOODX".
RecognizedProduct makeProduct({
  required num price,
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
  group.addMember(pos, opts.tuning);

  return product;
}

void main() {
  group('RecognizedProduct.isCashback / isDiscount / isDeposit', () {
    group('isCashback', () {
      test('true when price is negative', () {
        final p = makeProduct(
          price: -1.23,
          productText: 'ANY',
          priceLineText: '-1.23 NEUTRALTAG',
          options: ReceiptOptions.empty(),
        );
        expect(p.isCashback, isTrue);
      });

      test('false when price is positive or zero', () {
        final p1 = makeProduct(
          price: 0.00,
          productText: 'ANY',
          priceLineText: '0.00 NEUTRALTAG',
          options: ReceiptOptions.empty(),
        );
        final p2 = makeProduct(
          price: 2.49,
          productText: 'ANY',
          priceLineText: '2.49 NEUTRALTAG',
          options: ReceiptOptions.empty(),
        );
        expect(p1.isCashback, isFalse);
        expect(p2.isCashback, isFalse);
      });
    });

    group('isDiscount', () {
      test('true only when cashback AND discount keyword matches', () {
        final opts = makeOptionsFromLists(discount: ['SAVE']);
        final p = makeProduct(
          price: -0.40,
          productText: 'SAVE 10%',
          priceLineText: '-0.40 NEUTRALTAG',
          options: opts,
        );
        expect(p.isCashback, isTrue);
        expect(p.isDiscount, isTrue);
      });

      test('false when keyword matches but not cashback', () {
        final opts = makeOptionsFromLists(discount: ['SAVE']);
        final p = makeProduct(
          price: 0.40,
          productText: 'SAVE 10%',
          priceLineText: '0.40 NEUTRALTAG',
          options: opts,
        );
        expect(p.isCashback, isFalse);
        expect(p.isDiscount, isFalse);
      });

      test('false when cashback but keyword does not match', () {
        final opts = makeOptionsFromLists(discount: ['SAVE']);
        final p = makeProduct(
          price: -0.40,
          productText: 'NOT_A_DISCOUNT',
          priceLineText: '-0.40 NEUTRALTAG',
          options: opts,
        );
        expect(p.isCashback, isTrue);
        expect(p.isDiscount, isFalse);
      });
    });

    group('isDeposit', () {
      test('true when deposit keyword matches (custom option)', () {
        final opts = makeOptionsFromLists(deposit: ['DEPOSITX']);
        final p = makeProduct(
          price: 0.25,
          productText: 'DEPOSITX BOTTLE',
          priceLineText: '0.25 NEUTRALTAG',
          options: opts,
        );
        expect(p.isDeposit, isTrue);
      });

      test('false when no deposit keyword matches', () {
        final opts = makeOptionsFromLists(deposit: ['DEPOSITX']);
        final p = makeProduct(
          price: 0.25,
          productText: 'WATER',
          priceLineText: '0.25 NEUTRALTAG',
          options: opts,
        );
        expect(p.isDeposit, isFalse);
      });
    });
  });
  group('RecognizedProduct.isFood / isNonFood', () {
    test(
      'isFood=true when postfix matches a food keyword; isNonFood=false',
      () {
        final opts = makeOptionsFromLists(food: ['FOODX']);
        final p = makeProduct(
          price: 3.49,
          productText: 'ANY',
          priceLineText: '3.49 FOODX',
          options: opts,
        );
        expect(p.isFood, isTrue);
        expect(p.isNonFood, isFalse);
      },
    );

    test(
      'isNonFood=true when postfix matches a non-food keyword; isFood=false',
      () {
        final opts = makeOptionsFromLists(nonFood: ['NF_TAG']);
        final p = makeProduct(
          price: 2.99,
          productText: 'ANY',
          priceLineText: '2.99 NF_TAG',
          options: opts,
        );
        expect(p.isNonFood, isTrue);
        expect(p.isFood, isFalse);
      },
    );

    test('both false when no postfix keyword matches', () {
      final opts = makeOptionsFromLists(food: ['FOODX'], nonFood: ['NF_TAG']);
      final p = makeProduct(
        price: 1.00,
        productText: 'ANY',
        priceLineText: '1.00 NEUTRALTAG',
        options: opts,
      );
      expect(p.isFood, isFalse);
      expect(p.isNonFood, isFalse);
    });

    test(
      'with both lists provided: matches FOOD when postfix contains food token',
      () {
        final opts = makeOptionsFromLists(food: ['FOODX'], nonFood: ['NF_TAG']);
        final p = makeProduct(
          price: 0.79,
          productText: 'ANY',
          priceLineText: '0.79 FOODX',
          options: opts,
        );
        expect(p.isFood, isTrue);
        expect(p.isNonFood, isFalse);
      },
    );

    test(
      'with both lists provided: matches NON-FOOD when postfix contains non-food token',
      () {
        final opts = makeOptionsFromLists(food: ['FOODX'], nonFood: ['NF_TAG']);
        final p = makeProduct(
          price: 5.49,
          productText: 'ANY',
          priceLineText: '5.49 NF_TAG',
          options: opts,
        );
        expect(p.isFood, isFalse);
        expect(p.isNonFood, isTrue);
      },
    );
  });
}
