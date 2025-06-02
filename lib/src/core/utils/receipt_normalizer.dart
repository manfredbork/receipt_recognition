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
    final List<String> normalizedTexts = [];
    for (final frequencyText in frequencyTexts) {
      final text = normalizeTail(
        normalizeSpecialSpaces(frequencyText, frequencyTexts),
      );
      normalizedTexts.add(text);
    }
    final normalizedText = normalizeSpecialChars(
      normalizedTexts.last,
      normalizedTexts,
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

  /// Normalizes special characters by comparing with alternative recognitions.
  ///
  /// Improves text quality by replacing problematic characters with more likely
  /// alternatives based on comparisons with other recognized versions.
  static String normalizeSpecialChars(
    String bestText,
    List<String> otherTexts,
  ) {
    String normalizedText = '';
    for (int i = 0; i < otherTexts.length; i++) {
      final differentValue = bestText != otherTexts[i];
      final sameLength = bestText.length == otherTexts[i].length;
      if (differentValue && sameLength) {
        normalizedText = '';
        for (int j = 0; j < bestText.length; j++) {
          final char = bestText[j];
          final compareChar = otherTexts[i][j];
          if (RegExp(r'[@#^*()?":{}|<>]').hasMatch(char) &&
              RegExp(r'[A-Za-z0-9]').hasMatch(compareChar)) {
            normalizedText += compareChar;
          } else if (RegExp(r'[^A-Za-z ]').hasMatch(char) &&
              RegExp(r'[A-Za-zßàâäèéêëîïôœùûüÿçÀÂÄÈÉÊËÎÏÔŒÙÛÜŸÇ]').hasMatch(compareChar)) {
            normalizedText += compareChar;
          } else {
            normalizedText += char;
          }
        }
        bestText = normalizedText;
      }
    }
    if (normalizedText.isEmpty) {
      return bestText;
    }
    return normalizedText;
  }

  /// Normalizes spaces by analyzing word boundaries across multiple recognitions.
  ///
  /// Addresses issues with inconsistent spacing by comparing token patterns
  /// across multiple versions of the same text.
  static String normalizeSpecialSpaces(
    String bestText,
    List<String> otherTexts,
  ) {
    const separator = ' ';
    final bestTokens = bestText.split(separator);
    for (int i = 0; i < otherTexts.length; i++) {
      final otherTokens = otherTexts[i].split(separator);
      if (bestTokens.length > otherTokens.length) {
        for (int j = 1; j < bestTokens.length; j++) {
          if (j <= otherTokens.length) {
            final firstToken = bestTokens[j - 1];
            final secondToken =
                bestTokens[j] == bestTokens[j].toUpperCase()
                    ? bestTokens[j].toUpperCase()
                    : bestTokens[j].toLowerCase();
            final mergedToken = firstToken + secondToken;
            if (mergedToken == otherTokens[j - 1]) {
              bestTokens[j - 1] = mergedToken;
              bestTokens.removeAt(j);
              j--;
            }
          }
        }
      }
    }
    return bestTokens.join(separator);
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
