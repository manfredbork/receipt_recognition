import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedGroup {
  final List<RecognizedPosition> _members;
  final int _maxGroupSize;

  RecognizedGroup({maxGroupSize = 1})
    : _members = [],
      _maxGroupSize = max(1, maxGroupSize);

  void addMember(RecognizedPosition position) {
    position.group = this;

    if (_members.length >= _maxGroupSize) {
      _members.removeAt(0);
    }

    _members.add(position);
  }

  int calculateProductConfidence(RecognizedProduct product) {
    final total = _members.fold(
      0,
      (a, b) =>
          a +
          max(
            partialRatio(product.value, b.product.value),
            ratio(product.value, b.product.value),
          ),
    );
    return (total / _members.length).toInt();
  }

  int calculatePriceConfidence(RecognizedPrice price) {
    final total = _members.fold(
      0,
      (a, b) =>
          a +
          (min(price.value.abs(), b.price.value.abs()) /
                  max(price.value.abs(), b.price.value.abs()) *
                  100)
              .toInt(),
    );

    return (total / _members.length).toInt();
  }

  List<RecognizedPosition> get members => _members;

  List<String> get alternativeTexts =>
      _members.map((p) => p.product.text).toList();

  int get confidence {
    final total = _members.fold(0, (a, b) => a + b.confidence);
    return (total / _members.length).toInt();
  }

  int get stability => (_members.length / _maxGroupSize * 100).toInt();
}
