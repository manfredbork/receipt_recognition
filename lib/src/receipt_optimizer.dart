import 'package:intl/intl.dart';

import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition by multiple scans of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Precision level of optimization
  final PrecisionLevel _precisionLevel;

  /// Cached position from multiple scans
  final Map<String, List<String>> _cachedPositions;

  /// Cached sum from multiple scans
  RecognizedSum? _cachedSum;

  /// Cached company from multiple scans
  RecognizedCompany? _cachedCompany;

  /// Indicator if reinit happens
  bool _reinit = false;

  /// Constructor to create an instance of [ReceiptRecognizer].
  ReceiptOptimizer({PrecisionLevel precisionLevel = PrecisionLevel.high})
    : _precisionLevel = precisionLevel,
      _cachedPositions = {};

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (_reinit) {
      _cachedPositions.clear();
      _cachedSum = null;
      _cachedCompany = null;
      _reinit = false;
    }
    _cachedSum ??= receipt.sum;
    _cachedCompany ??= receipt.company;
    if (isValidReceipt(receipt)) {
      _reinit = true;
    }
    for (final position in receipt.positions) {
      final key = position.price.formattedValue;
      final value = position.product.value;
      if (_cachedPositions.containsKey(key) &&
          (_cachedPositions[key]?.length ?? 0) < _precisionLevel.index * 16) {
        _cachedPositions[key]?.add(value);
      } else {
        _cachedPositions[key] = [];
      }
    }
    return receipt;
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
