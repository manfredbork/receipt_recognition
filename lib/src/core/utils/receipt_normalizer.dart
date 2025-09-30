/// Utility for normalizing and standardizing recognized text from receipts.
///
/// Provides methods to improve text quality by applying various normalization
/// techniques and comparing against alternative recognitions.
final class ReceiptNormalizer {
  /// Normalizes text by comparing multiple alternative recognitions.
  ///
  /// Uses a consensus approach to improve accuracy by analyzing patterns
  /// across multiple recognitions of the same text.
  static String? normalizeByAlternativeTexts(List<String> alternativeTexts) {
    if (alternativeTexts.isEmpty) return null;
    final frequencyTexts = sortByFrequency(alternativeTexts);
    final normalizedText = normalizeTail(
      normalizeSpecialSpaces(frequencyTexts.last, frequencyTexts),
    );
    return normalizedText;
  }

  /// Normalizes the tail part of product text by removing price information.
  ///
  /// Removes trailing price-like patterns from product descriptions and
  /// limits the overall length for consistent processing.
  static String normalizeTail(String value) {
    String replacedValue = value.replaceAllMapped(
      RegExp(r'(.*\S)(\s*\d+[.,]?\d{2,3}.*)'),
      (match) => '${match[1]}',
    );
    if (RegExp(r'(\s*\d+[.,]?\d{2}\sEURO?)').hasMatch(value)) {
      replacedValue = value;
    }
    final replacedTokens = replacedValue.split(' ');
    String shortenValue = '';
    for (final token in replacedTokens) {
      shortenValue += shortenValue.isEmpty ? token : ' $token';
      if (shortenValue.length > 16) {
        break;
      }
    }
    return shortenValue;
  }

  /// Normalizes spaces by analyzing multiple recognitions.
  ///
  /// Addresses issues with inconsistent spacing by comparing
  /// across multiple versions of the same text.
  static String normalizeSpecialSpaces(
    String bestText,
    List<String> otherTexts,
  ) {
    const sep = ' ';
    final searchText = bestText.split(sep).join();
    final sameTexts =
        otherTexts
            .where(
              (t) =>
                  t.split(sep).join() == searchText &&
                  t.length < bestText.length,
            )
            .toList();
    if (sameTexts.isNotEmpty) {
      final minLen = sameTexts.fold<int>(
        sameTexts.first.length,
        (m, s) => s.length < m ? s.length : m,
      );
      return sameTexts.firstWhere((s) => s.length == minLen);
    }
    return bestText;
  }

  /// Sorts a list of strings by their frequency of occurrence.
  ///
  /// Returns a list ordered from least to most frequent, which helps
  /// identify the most common (likely correct) versions of text.
  static List<String> sortByFrequency(List<String> values) {
    final Map<String, int> frequencyMap = {};
    for (final value in values) {
      frequencyMap[value] = (frequencyMap[value] ?? 0) + 1;
    }
    final entries =
        frequencyMap.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
    return entries.map((e) => e.key).toList();
  }
}
