import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition by multiple scans of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Precision level of optimization
  final PrecisionLevel _precisionLevel;

  /// Indicator if reinit happens
  bool _reinit = false;

  /// Cached position from multiple scans
  List<CachedPosition>? _cachedPositions;

  /// Cached sum from multiple scans
  RecognizedSum? _cachedSum;

  /// Cached company from multiple scans
  RecognizedCompany? _cachedCompany;

  /// Constructor to create an instance of [ReceiptRecognizer].
  ReceiptOptimizer({PrecisionLevel precisionLevel = PrecisionLevel.high})
    : _precisionLevel = precisionLevel;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (_reinit) {
      _cachedPositions = null;
      _cachedSum = null;
      _cachedCompany = null;
      _reinit = false;
    }
    _cachedPositions ??= [];
    _cachedSum = receipt.sum ?? _cachedSum;
    _cachedCompany = receipt.company ?? _cachedCompany;
    if (isPrecisionLevelReached() && isValidReceipt(receipt)) {
      _reinit = true;
    }
    return receipt;
  }

  /// Checks if precision level is reached. Returns a [bool].
  bool isPrecisionLevelReached() {
    return _precisionLevel.index >= 0;
  }

  /// Checks if [RecognizedReceipt] is valid. Returns a [bool].
  bool isValidReceipt(RecognizedReceipt receipt) {
    return calculateSum(receipt.positions) == receipt.sum?.formattedValue;
  }

  /// Adds up prices of positions and formats sum. Returns a [String].
  String calculateSum(List<RecognizedPosition> positions) {
    return NumberFormat.decimalPatternDigits(
      locale: Intl.defaultLocale,
      decimalDigits: 2,
    ).format(positions.fold(0.0, (a, b) => a + b.price.value));
  }
}
