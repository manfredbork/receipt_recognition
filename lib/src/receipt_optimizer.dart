import 'receipt_models.dart';

/// A receipt optimizer that improves text recognition of [RecognizedReceipt].
class ReceiptOptimizer {
  /// Cached receipts from multiple scans
  static final List<RecognizedReceipt> _cachedReceipts = [];

  /// Indicator if reinit happens
  static bool _reinit = false;

  /// Optimizes the [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt optimizeReceipt(RecognizedReceipt receipt) {
    if (_reinit) {
      _reinit = false;
      _cachedReceipts.clear();
    }

    _cachedReceipts.add(receipt);

    if (_cachedReceipts.length >= 10) {
      _reinit = true;
    }

    receipt = synchronizeSumAndCompany(receipt);
    receipt = mergeReceipts(receipt);

    return receipt;
  }

  /// Merges cached list of [RecognizedReceipt]. Returns a [RecognizedReceipt].
  static RecognizedReceipt mergeReceipts(RecognizedReceipt receipt) {
    RecognizedReceipt mergedReceipt = receipt;
    List<RecognizedPosition> mergedPositions = [];

    print(mergedReceipt.company);
    for (final position in mergedReceipt.positions) {
      print('${position.product.value} ${position.price.formattedValue}');
    }
    print(mergedReceipt.sum?.formattedValue);
    print(mergedReceipt.calculatedSum.formattedValue);

    if (mergedReceipt.isValid) {
      _reinit = true;
      return mergedReceipt;
    } else if (mergedReceipt.calculatedSum.value >
        (receipt.sum?.value ?? 0.0)) {
      _reinit = true;
      return receipt;
    }

    for (final cachedReceipt in _cachedReceipts) {
      final positions = cachedReceipt.positions;

      for (int i = 0; i < positions.length; i++) {
        final posBefore = i > 0 ? positions[i - 1] : null;
        final posCurrent = positions[i];
        final posAfter = i < positions.length - 1 ? positions[i + 1] : null;

        if (!mergedPositions.contains(posCurrent)) {
          final iBefore = mergedPositions.indexWhere((p) => p == posBefore);
          final iAfter = mergedPositions.indexWhere((p) => p == posAfter);

          if (iBefore >= 0) {
            mergedPositions.insert(iBefore, posCurrent);
          } else if (iAfter >= 0) {
            mergedPositions.insert(iAfter, posCurrent);
          } else {
            mergedPositions.add(posCurrent);
          }
        }
      }

      mergedReceipt = RecognizedReceipt(
        positions: mergedPositions,
        sum: receipt.sum,
        company: receipt.company,
      );
    }

    return receipt;
  }

  /// Synchronizes [RecognizedSum] and [RecognizedCompany]. Returns a [RecognizedReceipt].
  static RecognizedReceipt synchronizeSumAndCompany(RecognizedReceipt receipt) {
    RecognizedSum? sum = receipt.sum;
    RecognizedCompany? company = receipt.company;
    for (final cachedReceipt in _cachedReceipts) {
      if (sum != null && company != null) {
        return RecognizedReceipt(
          positions: receipt.positions,
          sum: cachedReceipt.sum,
          company: cachedReceipt.company,
        );
      }

      if (sum == null && cachedReceipt.sum != null) {
        sum = cachedReceipt.sum;
      }

      if (company == null && cachedReceipt.company != null) {
        company = cachedReceipt.company;
      }
    }

    return receipt;
  }
}
