import 'package:receipt_recognition/receipt_recognition.dart';

/// Provides normalization routines for recognized receipt content,
/// including cleaning and standardizing product names based on group consensus.
final class ReceiptNormalizer {
  /// Normalizes all product names in a [RecognizedReceipt] by analyzing
  /// the associated [PositionGroup] of each [RecognizedPosition].
  ///
  /// This includes:
  /// - Removing OCR artifacts
  /// - Normalizing decimal/percentage formatting
  /// - Resolving the most representative product name within each group
  static RecognizedReceipt normalize(RecognizedReceipt receipt) {
    final positions =
        receipt.positions.map((pos) {
          final normalizedName = normalizeFromGroup(pos.group);
          return pos.copyWith(
            product: RecognizedProduct(
              value: normalizedName,
              line: pos.product.line,
            ),
          );
        }).toList();

    return receipt.copyWith(positions: positions);
  }

  /// Returns the best representative product name from a group of
  /// [RecognizedPosition]s by cleaning all variants and selecting the
  /// most frequent version.
  ///
  /// This helps resolve minor OCR discrepancies, spacing issues, and
  /// unwanted suffixes or symbols.
  static String normalizeFromGroup(PositionGroup group) {
    final rawNames = group.positions.map((p) => p.product.value).toList();
    final cleaned = rawNames.map(_basicClean).toList();

    final frequency = <String, int>{};
    for (final name in cleaned) {
      frequency[name] = (frequency[name] ?? 0) + 1;
    }

    final sorted =
        frequency.entries.toList()..sort((a, b) {
          final freqDiff = b.value.compareTo(a.value);
          return freqDiff;
        });

    return sorted.first.key;
  }

  /// Cleans a single product name string by:
  /// - Collapsing extra whitespace
  /// - Normalizing number formats (e.g. `"3 , 8 %"` → `"3,8%"`)
  /// - Removing trailing non-alphanumeric OCR noise
  ///
  /// This does not alter internal word spacing and is used as a
  /// building block for consensus-based group normalization.
  static String _basicClean(String input) {
    String text = input;

    text = text.replaceAll(RegExp(r'\s+'), ' ');

    text = ReceiptFormatter.normalizeCommas(text);

    final validEndPattern = RegExp(
      r'(ml|g|kg|l|%|x|Stk|Pack)$',
      caseSensitive: false,
    );
    final words = text.trim().split(' ');

    while (words.isNotEmpty) {
      final last = words.last;

      if (validEndPattern.hasMatch(last)) break;
      if (RegExp(r'^\d+[.,]?\d*%?$').hasMatch(last)) break;
      if (RegExp(r'^[^A-Za-z0-9äöüÄÖÜß]+$').hasMatch(last)) {
        words.removeLast();
        continue;
      }

      break;
    }

    return words.join(' ').trim();
  }
}
