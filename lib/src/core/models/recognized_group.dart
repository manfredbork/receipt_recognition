import 'dart:math';

import 'package:receipt_recognition/receipt_recognition.dart';

final class RecognizedGroup {
  final List<RecognizedPosition> _members;
  final int _maxGroupSize;

  RecognizedGroup({maxGroupSize = 10})
    : _members = [],
      _maxGroupSize = max(1, maxGroupSize);

  void addMember(RecognizedPosition position) {
    position.group = this;

    if (_members.length >= _maxGroupSize) {
      _members.removeAt(0);
    }

    _members.add(position);
  }

  List<String> get alternativeTexts =>
      _members.map((p) => p.product.text).toList();

  int get confidence {
    final confidences = _members.fold(0, (a, b) => a + b.confidence);
    return (confidences / _members.length).toInt();
  }

  int get stability => (_members.length / _maxGroupSize * 100).toInt();
}
