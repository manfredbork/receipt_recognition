import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Groups similar receipt positions together to improve recognition accuracy.
///
/// Tracks multiple recognitions of the same item across scans and provides
/// methods for confidence calculation and text normalization.
final class RecognizedGroup {
  final List<RecognizedPosition> _members;
  final int _maxGroupSize;

  /// Creates a new recognition group with a maximum size limit.
  ///
  /// The [maxGroupSize] controls how many members can be in the group before
  /// older ones are removed (FIFO).
  RecognizedGroup({int maxGroupSize = 1})
    : _members = [],
      _maxGroupSize = max(1, maxGroupSize);

  /// Adds a position to this group, maintaining size constraints.
  ///
  /// If the group is already at capacity, the oldest member is removed.
  void addMember(RecognizedPosition position) {
    position.group = this;

    if (_members.length >= _maxGroupSize) {
      _members.removeAt(0);
    }

    _members.add(position);
    recalculateAllConfidences();
  }

  /// Recalculates product and price confidences for all group members,
  /// ensuring the latest scores are used for optimization.
  ///
  /// This method is triggered when new members are added to the group.
  void recalculateAllConfidences() {
    for (final member in _members) {
      member.product.confidence = calculateProductConfidence(member.product);
      member.price.confidence = calculatePriceConfidence(member.price);
    }
  }

  /// Calculates an adaptive [Confidence] value for a product name based on its
  /// similarity to previously recognized group members.
  ///
  /// Uses fuzzy string matching (full ratio) and penalizes inconsistent matches
  /// using the standard deviation of scores. This helps prioritize stable and
  /// coherent groupings over noisy OCR data.
  ///
  /// Returns a [Confidence] instance where the value represents recognition
  /// certainty (0–100) and the weight reflects stability.
  Confidence calculateProductConfidence(RecognizedProduct product) {
    if (_members.isEmpty) return Confidence(value: 0);

    final scores =
        _members.map((b) => ratio(product.value, b.product.value)).toList();

    if (scores.isEmpty) return Confidence(value: 0);

    final average = scores.reduce((a, b) => a + b) / scores.length;

    final variance =
        scores
            .map((s) => (s - average) * (s - average))
            .reduce((a, b) => a + b) /
        scores.length;

    final stddev = sqrt(variance);
    final weight = stddev < 10 ? 1.0 : (100 - stddev) / 100;

    return Confidence(value: (average * weight).clamp(0, 100).toInt());
  }

  /// Calculates a [Confidence] value for a price based on numeric similarity.
  ///
  /// Compares the given price with existing members using a ratio approach,
  /// where smaller relative differences yield higher confidence.
  ///
  /// Returns a [Confidence] instance representing how reliably the price
  /// matches the group’s consensus (0–100 scale).
  Confidence calculatePriceConfidence(RecognizedPrice price) {
    if (_members.isEmpty || price.value == 0) return Confidence(value: 0);

    final scores =
        _members.map((b) {
          final diff = (price.value - b.price.value).abs();
          final ratio = diff / (price.value.abs() + b.price.value.abs()) * 100;
          return (100 - ratio).toInt();
        }).toList();

    final average = scores.reduce((a, b) => a + b) / scores.length;
    return Confidence(value: average.toInt());
  }

  /// Removes a leading amount pattern from [postfixText].
  ///
  /// Returns the remaining postfix string, or an empty string
  /// if no valid amount prefix is found.
  String convertToPostfixText(String postfixText) {
    if (postfixText.isEmpty) return postfixText;
    final amountMatch = ReceiptPatterns.amount.matchAsPrefix(
      postfixText.trim(),
    );
    if (amountMatch == null) return '';
    return postfixText.substring(amountMatch.end).trim();
  }

  /// Gets all position members in this group.
  List<RecognizedPosition> get members => _members;

  /// Gets all product texts from group members for normalization.
  List<String> get alternativeTexts =>
      _members.map((p) => p.product.text).toList();

  /// Gets all product postfix texts from group members to categorize.
  List<String> get alternativePostfixTexts =>
      _members.map((p) => convertToPostfixText(p.price.line.text)).toList();

  /// Gets the average confidence score across all members.
  int get confidence {
    final total = _members.fold(0, (a, b) => a + b.confidence);
    return (total / _members.length).toInt();
  }

  /// Gets the average stability score across all members.
  int get stability {
    final total = _members.fold(0, (a, b) => a + b.stability);
    return (total / _members.length).toInt();
  }

  /// Gets the most recent timestamp from all members.
  DateTime get timestamp {
    if (_members.isEmpty) {
      return DateTime.now();
    }
    return _members
        .reduce((a, b) => a.timestamp.isAfter(b.timestamp) ? a : b)
        .timestamp;
  }
}
