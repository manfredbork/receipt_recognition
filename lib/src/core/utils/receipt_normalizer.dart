final class ReceiptNormalizer {
  static String normalize(String value) {
    final removedNoisySpaces = _removeNoisySpaces(value);
    final removedNoisyTail = _removeNoisyTail(removedNoisySpaces);
    return removedNoisyTail;
  }

  static String trim(String value) {
    return _removeNoisySpaces(value);
  }

  static String _removeNoisySpaces(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)\s*([,.])\s*(\S*)'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }

  static String _removeNoisyTail(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)(-?\s*\d+\s*[.,]\s*\d{2}.*)'),
      (match) => '${match[1]}',
    );
  }

  static String normalizeByAllValues(List<String> values) {
    final sorted = _sortByFrequency(values);
    final normalized = _normalizeSpecialChars(sorted);
    if (sorted.isNotEmpty && normalized.isEmpty) {
      return sorted.first;
    }
    return normalized;
  }

  static String _normalizeSpecialChars(List<String> values) {
    String normalized = '';
    for (int i = 1; i < values.length; i++) {
      final differentValue = values.first != values[i];
      final sameLength = values.first.length == values[i].length;
      if (differentValue && sameLength) {
        normalized = '';
        for (int j = 0; j < values.first.length; j++) {
          final char = values.first[j];
          final compareChar = values[i][j];
          if (RegExp(r'[#0-9]').hasMatch(char) &&
              RegExp(r'[A-Za-z]').hasMatch(compareChar)) {
            normalized += compareChar;
          } else if (RegExp(r'[A-Za-z0-9]').hasMatch(char) &&
              RegExp(r'[ÄÖÜäöüß]').hasMatch(compareChar)) {
            normalized += compareChar;
          } else {
            normalized += char;
          }
        }
        values.first = normalized;
      }
    }
    final normalizedToken = normalized.split(' ');
    for (int i = 1; i < values.length; i++) {
      final token = values[i].split(' ');
      if (normalizedToken.length > token.length) {
        for (int j = 0; j < normalizedToken.length; j++) {
          if (j + 1 < token.length) {
            final merged = normalizedToken[j] + normalizedToken[j + 1];
            if (merged == token[j]) {
              normalizedToken[j] = merged;
              normalizedToken.removeAt(j + 1);
              j--;
            }
          }
        }
      }
    }
    return normalizedToken.join(' ');
  }

  static List<String> _sortByFrequency(List<String> values) {
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
