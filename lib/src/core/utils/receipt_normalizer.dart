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
      RegExp(r'([0-9])\s*([,.])\s*([0-9])'),
      (match) => '${match[1]}${match[2]}${match[3]}',
    );
  }

  static String _removeNoisyTail(String value) {
    return value.replaceAllMapped(
      RegExp(r'(\S*)(-?\s*\d+\s*[.,]\s*\d{2})(\s[^EURO])(.*)'),
      (match) => '${match[1]}${match[3]}',
    );
  }

  static String normalizeByAllValues(List<String> values) {
    final sortedByFrequency = _sortByFrequency(values);
    String merged = '';
    for (int i = 1; i < sortedByFrequency.length; i++) {
      final differentValue = sortedByFrequency.first != sortedByFrequency[i];
      final sameLength =
          sortedByFrequency.first.length == sortedByFrequency[i].length;
      if (differentValue && sameLength) {
        merged = '';
        for (int j = 0; j < sortedByFrequency.first.length; j++) {
          final char = sortedByFrequency.first[j];
          final compareChar = sortedByFrequency[i][j];
          if (RegExp(r'[^A-Za-zäöüß]').hasMatch(char) &&
              RegExp(r'[A-Za-zäöüß]').hasMatch(compareChar)) {
            merged += compareChar;
          } else if (RegExp(r'[^äöüß]').hasMatch(char) &&
              RegExp(r'[äöüß]').hasMatch(compareChar)) {
            merged += compareChar;
          } else {
            merged += char;
          }
        }
      }
    }
    if (sortedByFrequency.isNotEmpty && merged.isEmpty) {
      return sortedByFrequency.first;
    }
    return merged;
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
