import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/src/models/index.dart';
import 'package:receipt_recognition/src/services/parser/index.dart';

/// Line item position on a receipt (product + price).
final class RecognizedPosition {
  /// Product part (name/description).
  final RecognizedProduct product;

  /// Price part.
  final RecognizedPrice price;

  /// When this position was recognized.
  DateTime timestamp;

  /// Operation performed (added, updated, etc.).
  Operation operation;

  /// Optional optimizer grouping.
  RecognizedGroup? group;

  /// Creates a [RecognizedPosition].
  RecognizedPosition({
    required this.product,
    required this.price,
    required this.timestamp,
    required this.operation,
    this.group,
  });

  /// Creates a [RecognizedPosition] from JSON.
  factory RecognizedPosition.fromJson(Map<String, dynamic> json) {
    return RecognizedPosition(
      product: RecognizedProduct.fromJson(json['product']),
      price: RecognizedPrice.fromJson(json['price']),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      operation: Operation.none,
    );
  }

  /// Returns a copy with updated fields.
  RecognizedPosition copyWith({
    RecognizedProduct? product,
    RecognizedPrice? price,
    DateTime? timestamp,
    Operation? operation,
    RecognizedGroup? group,
  }) {
    return RecognizedPosition(
      product: product ?? this.product,
      price: price ?? this.price,
      timestamp: timestamp ?? this.timestamp,
      operation: operation ?? this.operation,
      group: group ?? this.group,
    );
  }

  /// Overall confidence (weighted avg of product/price confidences).
  int get confidence {
    final pc = product.confidence;
    final prc = price.confidence;
    if (pc == null || prc == null) return 0;

    final w1 = pc.weight;
    final w2 = prc.weight;
    final denom = w1 + w2;
    if (denom == 0) return 0;

    final num = pc.value * w1 + prc.value * w2;
    return (num / denom).toInt();
  }

  /// Product text stability (consensus percentage).
  int get stability => product.textConsensusRatio;
}

/// Groups similar receipt positions together to improve recognition accuracy.
final class RecognizedGroup {
  final List<RecognizedPosition> _members;
  final int _maxGroupSize;

  /// Creates a new recognition group with a maximum size limit.
  RecognizedGroup({int maxGroupSize = 1})
    : _members = <RecognizedPosition>[],
      _maxGroupSize = max(1, maxGroupSize);

  /// Adds a position and enforces capacity.
  void addMember(RecognizedPosition position) {
    position.group = this;
    if (_members.length >= _maxGroupSize) _members.removeAt(0);
    _members.add(position);
    _recalculateAllConfidences();
  }

  /// Calculates an adaptive confidence for a product name based on similarity to group members.
  Confidence calculateProductConfidence(RecognizedProduct product) {
    if (_members.isEmpty) return const Confidence(value: 0);
    final scores =
        _members.map((b) => ratio(product.value, b.product.value)).toList();
    if (scores.isEmpty) return const Confidence(value: 0);

    var sum = 0.0, sumSq = 0.0;
    for (final s in scores) {
      sum += s;
      sumSq += s * s;
    }
    final n = scores.length;
    final avg = sum / n;
    final variance = (sumSq / n) - (avg * avg);
    final stddev = sqrt(max(0.0, variance));
    final weight = stddev < 10 ? 1.0 : (100 - stddev) / 100.0;

    return Confidence(value: (avg * weight).clamp(0, 100).toInt());
  }

  /// Calculates a confidence for a price based on numeric similarity.
  Confidence calculatePriceConfidence(RecognizedPrice price) {
    if (_members.isEmpty || price.value == 0) return const Confidence(value: 0);
    final scores =
        _members.map((b) {
          final diff = (price.value - b.price.value).abs();
          final denom = price.value.abs() + b.price.value.abs();
          final pctDiff = denom == 0 ? 100.0 : (diff / denom) * 100.0;
          return (100.0 - pctDiff).clamp(0, 100).toInt();
        }).toList();
    final avg = scores.reduce((a, b) => a + b) / scores.length;
    return Confidence(value: avg.toInt());
  }

  /// Removes a leading amount pattern from [postfixText], returning the remainder.
  String convertToPostfixText(String postfixText) {
    if (postfixText.isEmpty) return postfixText;
    final m = ReceiptPatterns.amount.matchAsPrefix(postfixText.trim());
    if (m == null) return '';
    return postfixText.substring(m.end).trim();
  }

  /// All position members.
  List<RecognizedPosition> get members => _members;

  /// All product texts for normalization.
  List<String> get alternativeTexts =>
      _members.map((p) => p.product.text).toList();

  /// All product postfix texts (amount prefix removed) for categorization.
  List<String> get alternativePostfixTexts =>
      _members.map((p) => convertToPostfixText(p.price.line.text)).toList();

  /// Average confidence across members.
  int get confidence {
    if (_members.isEmpty) return 0;
    final total = _members.fold<int>(0, (a, b) => a + b.confidence);
    return total ~/ _members.length;
  }

  /// Average stability across members.
  int get stability {
    if (_members.isEmpty) return 0;
    final total = _members.fold<int>(0, (a, b) => a + b.stability);
    return total ~/ _members.length;
  }

  /// Most recent timestamp across members.
  DateTime get timestamp {
    if (_members.isEmpty) return DateTime.now();
    return _members
        .reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b)
        .timestamp;
  }

  /// Recomputes confidences for all members.
  void _recalculateAllConfidences() {
    for (final m in _members) {
      m.product.confidence = calculateProductConfidence(m.product);
      m.price.confidence = calculatePriceConfidence(m.price);
    }
  }
}
