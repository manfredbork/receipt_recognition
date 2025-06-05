import 'package:collection/collection.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Interface for receipt optimization components.
///
/// Optimizers improve recognition accuracy by processing and refining receipt data
/// over multiple scans.
abstract class Optimizer {
  /// Initializes or resets the optimizer state.
  void init();

  /// Processes a receipt to improve its recognition quality.
  ///
  /// Returns an optimized version of the input receipt.
  RecognizedReceipt optimize(RecognizedReceipt receipt);

  /// Releases resources used by the optimizer.
  void close();
}

/// Default implementation of receipt optimizer that uses confidence scoring and grouping.
///
/// Improves recognition accuracy by:
/// - Grouping similar items together
/// - Applying confidence thresholds
/// - Merging data from multiple scans
final class ReceiptOptimizer implements Optimizer {
  final List<RecognizedGroup> _groups = [];
  final List<RecognizedCompany> _companies = [];
  final List<RecognizedSum> _sums = [];
  final List<_SumCandidate> _sumCandidates = [];
  final int _loopThreshold = 3;
  final int _sumConfirmationThreshold;
  final int _maxCacheSize;
  final int _confidenceThreshold;
  final int _stabilityThreshold;
  final Duration _invalidateInterval;

  bool _shouldInitialize;
  int _unchangedCount = 0;
  String? _lastFingerprint;

  /// Creates a new receipt optimizer with configurable thresholds.
  ///
  /// Parameters:
  /// - [sumConfirmationThreshold]: Minimum number of matching detections to confirm a sum
  /// - [maxCacheSize]: Maximum number of items to keep in memory
  /// - [confidenceThreshold]: Minimum confidence score (0-100) for matching
  /// - [stabilityThreshold]: Minimum stability score (0-100) for groups
  /// - [invalidateInterval]: Time after which unstable groups are removed
  ReceiptOptimizer({
    int sumConfirmationThreshold = 2,
    int maxCacheSize = 50,
    int confidenceThreshold = 75,
    int stabilityThreshold = 50,
    Duration invalidateInterval = const Duration(seconds: 1),
  }) : _sumConfirmationThreshold = sumConfirmationThreshold,
       _maxCacheSize = maxCacheSize,
       _confidenceThreshold = confidenceThreshold,
       _stabilityThreshold = stabilityThreshold,
       _invalidateInterval = invalidateInterval,
       _shouldInitialize = false;

  /// Marks the optimizer for reinitialization on next optimization.
  @override
  void init() {
    _shouldInitialize = true;
  }

  /// Processes a receipt to improve its recognition quality.
  ///
  /// Applies various optimization strategies including:
  /// - Company name normalization
  /// - Sum validation and correction
  /// - Position grouping and confidence scoring
  @override
  RecognizedReceipt optimize(RecognizedReceipt receipt) {
    if (!_checkConvergence(receipt)) {
      return receipt;
    }

    _initializeIfNeeded();
    _updateCompanies(receipt);
    _updateSums(receipt);
    _optimizeCompany(receipt);
    _optimizeSum(receipt);
    _cleanupGroups();
    _resetOperations();
    _processPositions(receipt);

    return _createOptimizedReceipt(receipt);
  }

  void _initializeIfNeeded() {
    if (_shouldInitialize) {
      _groups.clear();
      _companies.clear();
      _sums.clear();
      _shouldInitialize = false;
    }
  }

  bool _checkConvergence(RecognizedReceipt receipt) {
    final positionsHash = receipt.positions
        .map((p) => '${p.product.value}:${p.price.value}')
        .join(',');
    final sumHash = receipt.sum?.formattedValue ?? '';
    final fingerprint = '$positionsHash|$sumHash';

    if (_lastFingerprint == fingerprint) {
      _unchangedCount++;
      if (_unchangedCount >= _loopThreshold) {
        return false;
      }
    } else {
      _unchangedCount = 0;
    }

    _lastFingerprint = fingerprint;
    return true;
  }

  void _updateCompanies(RecognizedReceipt receipt) {
    if (receipt.company != null) {
      _companies.add(receipt.company!);
    }

    if (_companies.length > _maxCacheSize) {
      _companies.removeAt(0);
    }
  }

  void _updateSums(RecognizedReceipt receipt) {
    if (receipt.sum != null) {
      _sums.add(receipt.sum!);

      final sumLabel = receipt.entities
          ?.whereType<RecognizedSumLabel>()
          .firstWhereOrNull(
            (label) =>
                (label.line.boundingBox.top - receipt.sum!.line.boundingBox.top)
                    .abs() <
                ReceiptConstants.boundingBoxBuffer,
          );

      if (sumLabel != null) {
        final candidate = _SumCandidate(
          label: sumLabel,
          sum: receipt.sum!,
          verticalDistance:
              (sumLabel.line.boundingBox.top -
                      receipt.sum!.line.boundingBox.top)
                  .abs()
                  .toInt(),
        );

        final existing =
            _sumCandidates.where((c) => c.matches(candidate)).firstOrNull;
        if (existing != null) {
          existing.confirm();
        } else {
          _sumCandidates.add(candidate);
        }

        if (_sumCandidates.length > _maxCacheSize) {
          _sumCandidates.removeAt(0);
        }
      }
    }
  }

  void _optimizeCompany(RecognizedReceipt receipt) {
    if (receipt.company == null && _companies.isNotEmpty) {
      final lastCompany = _companies.lastOrNull;
      if (lastCompany != null) {
        final mostFrequent =
            ReceiptNormalizer.sortByFrequency(
              _companies.map((c) => c.value).toList(),
            ).lastOrNull;
        receipt.company = lastCompany.copyWith(value: mostFrequent);
      }
    }
  }

  void _optimizeSum(RecognizedReceipt receipt) {
    if (receipt.sum == null && _sums.isNotEmpty) {
      final sum =
          ReceiptNormalizer.sortByFrequency(
            _sums.map((c) => c.formattedValue).toList(),
          ).lastOrNull;
      if (sum != null) {
        receipt.sum = _sums.last.copyWith(value: ReceiptFormatter.parse(sum));
      }
    }
  }

  void _cleanupGroups() {
    if (_groups.length >= _maxCacheSize) {
      DateTime now = DateTime.now();
      _groups.removeWhere(
        (g) =>
            now.difference(g.timestamp) >= _invalidateInterval &&
            g.stability < _stabilityThreshold,
      );
    }
  }

  void _resetOperations() {
    for (final group in _groups) {
      for (final position in group.members) {
        position.operation = Operation.none;
      }
    }
  }

  void _processPositions(RecognizedReceipt receipt) {
    final stableSum = minBy(
      _sumCandidates.where((c) => c.confirmations >= _sumConfirmationThreshold),
      (c) => c.verticalDistance,
    );

    final isWaitingForSumConfirmation = receipt.isValid && stableSum == null;

    if (isWaitingForSumConfirmation) {
      return;
    }

    for (final position in receipt.positions) {
      if (stableSum != null &&
          (position.price.value - stableSum.sum.value).abs() < 0.01) {
        if (stableSum.confirmations >= _sumConfirmationThreshold) {
          continue;
        }
      }

      if (stableSum != null &&
          position.product.value == stableSum.label.line.text) {
        continue;
      }

      _processPosition(position);
    }
  }

  void _processPosition(RecognizedPosition position) {
    int bestConfidence = 0;
    RecognizedGroup? bestGroup;

    for (final group in _groups) {
      final result = _calculateConfidence(position, group, bestConfidence);
      if (result.shouldUseGroup) {
        bestConfidence = result.confidence;
        bestGroup = group;
        position.product.confidence = result.productConfidence;
        position.price.confidence = result.priceConfidence;
      }
    }

    if (bestGroup == null) {
      _createNewGroup(position);
    } else {
      _addToExistingGroup(position, bestGroup);
    }
  }

  _ConfidenceResult _calculateConfidence(
    RecognizedPosition position,
    RecognizedGroup group,
    int currentBestConfidence,
  ) {
    final int productConfidence = group.calculateProductConfidence(
      position.product,
    );
    final int priceConfidence = group.calculatePriceConfidence(position.price);
    final int confidence =
        ((3 * productConfidence + priceConfidence) / 4).toInt();
    final bool sameTimestamp = group.members.any(
      (p) => position.timestamp == p.timestamp,
    );

    final shouldUseGroup =
        !sameTimestamp &&
        confidence >= _confidenceThreshold &&
        confidence > currentBestConfidence;

    return _ConfidenceResult(
      productConfidence: productConfidence,
      priceConfidence: priceConfidence,
      confidence: confidence,
      shouldUseGroup: shouldUseGroup,
    );
  }

  void _createNewGroup(RecognizedPosition position) {
    final newGroup = RecognizedGroup(maxGroupSize: _maxCacheSize);
    position.group = newGroup;
    position.operation = Operation.added;
    newGroup.addMember(position);
    _groups.add(newGroup);
  }

  void _addToExistingGroup(RecognizedPosition position, RecognizedGroup group) {
    position.group = group;
    position.operation = Operation.updated;
    group.addMember(position);
  }

  RecognizedReceipt _createOptimizedReceipt(RecognizedReceipt receipt) {
    final stableGroups = _groups.where(
      (g) => g.stability >= _stabilityThreshold,
    );

    if (stableGroups.isEmpty) return receipt;

    final mergedReceipt = RecognizedReceipt.empty();

    for (final group in stableGroups) {
      final best = maxBy(group.members, (p) => p.confidence);
      if (best != null) {
        mergedReceipt.positions.add(best);
      }

      if (mergedReceipt.positions.length >= receipt.positions.length) break;
    }

    mergedReceipt.company = receipt.company;
    mergedReceipt.sum = receipt.sum;

    _removeSingleOutlierToMatchSum(mergedReceipt);

    final isBetter =
        mergedReceipt.isValid ||
        mergedReceipt.positions.length >= receipt.positions.length;

    return isBetter ? mergedReceipt : receipt;
  }

  void _removeSingleOutlierToMatchSum(RecognizedReceipt receipt) {
    final target = receipt.sum?.value;
    if (target == null || receipt.positions.length <= 1) return;

    for (final position in receipt.positions) {
      final testSum = receipt.positions
          .where((p) => p != position)
          .fold<double>(0.0, (sum, p) => sum + p.price.value);

      if ((testSum - target).abs() < 0.01) {
        final group = position.group;
        if (group != null) {
          group.members.remove(position);
        }
        receipt.positions.remove(position);
        break;
      }
    }
  }

  /// Releases all resources used by the optimizer.
  ///
  /// Clears all cached groups, companies, and sums.
  @override
  void close() {
    _groups.clear();
    _companies.clear();
    _sums.clear();
    _shouldInitialize = false;
  }
}

class _ConfidenceResult {
  final int productConfidence;
  final int priceConfidence;
  final int confidence;
  final bool shouldUseGroup;

  _ConfidenceResult({
    required this.productConfidence,
    required this.priceConfidence,
    required this.confidence,
    required this.shouldUseGroup,
  });
}

class _SumCandidate {
  final RecognizedSumLabel label;
  final RecognizedSum sum;
  final int verticalDistance;
  int confirmations = 1;

  _SumCandidate({
    required this.label,
    required this.sum,
    required this.verticalDistance,
  });

  bool matches(_SumCandidate other) =>
      label.line.text == other.label.line.text &&
      (sum.value - other.sum.value).abs() < 0.01;

  void confirm() => confirmations++;
}
