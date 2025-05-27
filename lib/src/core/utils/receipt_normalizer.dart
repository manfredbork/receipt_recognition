final class ReceiptNormalizer {
  static String normalizeByAlternativeTexts(
    String bestText,
    List<String> otherTexts,
  ) {
    final frequencyTexts = sortByFrequency(otherTexts);
    final firstStageText = normalizeSpecialChars(bestText, frequencyTexts);
    final secondStageText = normalizeSpecialSpaces(
      firstStageText,
      frequencyTexts,
    );
    final normalizedText = normalizeTail(secondStageText);
    return normalizedText;
  }

  static String normalizeTail(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)(-?\s*\d+\s*[.,]\s*\d{2}.*)'),
      (match) => '${match[1]}',
    );
  }

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
          if (RegExp(r'[!@#^*()?":{}|<>]').hasMatch(char) &&
              RegExp(r'[A-Za-z0-9]').hasMatch(compareChar)) {
            normalizedText += compareChar;
          } else if (RegExp(r'[^ÄÖÜäöüß]').hasMatch(char) &&
              RegExp(r'[ÄÖÜäöüß]').hasMatch(compareChar)) {
            normalizedText += compareChar;
          } else if (RegExp(r'[0-9]').hasMatch(char) &&
              RegExp(r'[A-Za-z]').hasMatch(compareChar)) {
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

  static String normalizeSpecialSpaces(
    String bestText,
    List<String> otherTexts,
  ) {
    const separator = ' ';
    for (int i = 0; i < otherTexts.length; i++) {
      final bestTokens = bestText.split(separator);
      final otherTokens = otherTexts[i].split(separator);
      if (bestTokens.length > otherTokens.length) {
        for (int j = 0; j < bestTokens.length; j++) {
          if (j + 1 < otherTokens.length) {
            final mergedToken = bestTokens[j] + bestTokens[j + 1];
            if (mergedToken == otherTokens[j]) {
              bestTokens[j] = mergedToken;
              bestTokens.removeAt(j + 1);
              j--;
            }
          }
        }
      }
      bestText = bestTokens.join(separator);
    }
    return bestText;
  }

  static List<String> sortByFrequency(List<String> values) {
    final Map<String, int> frequencyMap = {};
    for (final value in values) {
      frequencyMap[value] = (frequencyMap[value] ?? 0) + 1;
    }
    final entries =
        frequencyMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return entries.map((e) => e.key).toList();
  }
}
