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
  final int _maxCacheSize;
  final int _confidenceThreshold;
  final int _stabilityThreshold;
  final Duration _invalidateInterval;

  bool _shouldInitialize;

  /// Creates a new receipt optimizer with configurable thresholds.
  ///
  /// Parameters:
  /// - [maxCacheSize]: Maximum number of items to keep in memory
  /// - [confidenceThreshold]: Minimum confidence score (0-100) for matching
  /// - [stabilityThreshold]: Minimum stability score (0-100) for groups
  /// - [invalidateInterval]: Time after which unstable groups are removed
  ReceiptOptimizer({
    int maxCacheSize = 20,
    int confidenceThreshold = 75,
    int stabilityThreshold = 75,
    Duration invalidateInterval = const Duration(seconds: 2),
  }) : _maxCacheSize = maxCacheSize,
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
    _initializeIfNeeded();
    _updateCompanies(receipt);
    _updateSums(receipt);
    _optimizeCompany(receipt);
    _optimizeSum(receipt);
    _cleanupGroups();
    _processPositions(receipt);

    return _createOptimizedReceipt(receipt);
  }

  /// Releases all resources used by the optimizer.
  void _initializeIfNeeded() {
    if (_shouldInitialize) {
      _groups.clear();
      _companies.clear();
      _sums.clear();
      _shouldInitialize = false;
    }
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
    }

    if (_sums.length > _maxCacheSize) {
      _sums.removeAt(0);
    }
  }

  void _optimizeCompany(RecognizedReceipt receipt) {
    if (receipt.company == null && _companies.isNotEmpty) {
      final company = ReceiptNormalizer.sortByFrequency(
        _companies.map((c) => c.value).toList(),
      );
      receipt.company = _companies.last.copyWith(value: company.last);
    }
  }

  void _optimizeSum(RecognizedReceipt receipt) {
    if (receipt.sum == null && _sums.isNotEmpty) {
      final sum = ReceiptNormalizer.sortByFrequency(
        _sums.map((c) => c.formattedValue).toList(),
      );
      receipt.sum = _sums.last.copyWith(
        value: ReceiptFormatter.parse(sum.last),
      );
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

  void _processPositions(RecognizedReceipt receipt) {
    for (final position in receipt.positions) {
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
        ((4 * productConfidence + priceConfidence) / 5).toInt();
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
    newGroup.addMember(position);
    _groups.add(newGroup);
  }

  void _addToExistingGroup(RecognizedPosition position, RecognizedGroup group) {
    position.group = group;
    group.addMember(position);
  }

  RecognizedReceipt _createOptimizedReceipt(RecognizedReceipt receipt) {
    final stableGroups = _groups.where(
      (g) => g.stability >= _stabilityThreshold,
    );

    if (stableGroups.isEmpty || receipt.isValid) {
      return receipt;
    }

    final RecognizedReceipt mergedReceipt = RecognizedReceipt.empty();
    for (final group in stableGroups) {
      final position = group.members.reduce(
        (a, b) => a.confidence > b.confidence ? a : b,
      );
      mergedReceipt.positions.add(position);
      if (mergedReceipt.isValid) break;
    }

    return receipt.copyWith(positions: mergedReceipt.positions);
  }

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
