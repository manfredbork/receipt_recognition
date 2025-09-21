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

  /// Calculates an adaptive confidence score for a product name based on similarity
  /// to previously recognized group members.
  ///
  /// Uses fuzzy string matching (partial and full ratio) and penalizes inconsistent
  /// matches using the standard deviation of scores. This helps prioritize stable
  /// and coherent groupings over noisy OCR data.
  ///
  /// Returns an integer score between 0–100 indicating confidence.
  int calculateProductConfidence(RecognizedProduct product) {
    if (_members.isEmpty) return 0;

    final scores =
        _members.map((b) {
          final partial = partialRatio(product.value, b.product.value);
          final full = ratio(product.value, b.product.value);
          return max(partial, full);
        }).toList();

    if (scores.isEmpty) return 0;

    final average = scores.reduce((a, b) => a + b) / scores.length;

    final variance =
        scores
            .map((s) => (s - average) * (s - average))
            .reduce((a, b) => a + b) /
        scores.length;

    final stddev = sqrt(variance);
    final weight = stddev < 10 ? 1.0 : (100 - stddev) / 100;

    return (average * weight).clamp(0, 100).toInt();
  }

  /// Calculates confidence score for a price based on numeric similarity.
  ///
  /// Compares the price value with existing members using a ratio approach.
  /// Returns a score from 0-100 indicating confidence level.
  int calculatePriceConfidence(RecognizedPrice price) {
    if (_members.isEmpty) return 0;

    final scores =
        _members.map((b) {
          final minVal = min(price.value.abs(), b.price.value.abs());
          final maxVal = max(price.value.abs(), b.price.value.abs());
          return (minVal / maxVal * 100).toInt();
        }).toList();

    final average = scores.reduce((a, b) => a + b) / scores.length;
    return average.toInt();
  }

  /// Gets all position members in this group.
  List<RecognizedPosition> get members => _members;

  /// Gets all product texts from group members for normalization.
  List<String> get alternativeTexts =>
      _members.map((p) => p.product.text).toList();

  /// Gets the average confidence score across all members.
  int get confidence {
    final total = _members.fold(0, (a, b) => a + b.confidence);
    return (total / _members.length).toInt();
  }

  /// Gets the stability score (0-100) based on current vs. maximum size.
  ///
  /// Higher stability indicates more consistent recognitions over time.
  int get stability => (_members.length / _maxGroupSize * 100).toInt();

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
