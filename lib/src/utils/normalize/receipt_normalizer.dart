import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';

/// Utility for normalizing and standardizing recognized text from receipts.
final class ReceiptNormalizer {
  /// All common Unicode whitespace characters.
  static final RegExp _allSpaces = RegExp(
    r'[\u0009-\u000D\u0020\u0085\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
  );

  /// Product group disallowed chars
  static final RegExp _disallowedGroupChars = RegExp(r'[^A-Za-z0-9]');

  /// Collapse all Unicode spaces to a normal space first.
  static String _normalizeSpaces(String s) =>
      s.replaceAll(_allSpaces, ' ').trim();

  /// Normalizes postfix text to a product group. If `ReceiptRuntime.options`
  /// defines `allowedProductGroups` and the normalized value is not contained
  /// this returns ''.
  static String normalizeToProductGroup(String postfixText) {
    final cleaned = postfixText.replaceAll(_disallowedGroupChars, '');
    if (cleaned.isEmpty) return '';

    final allowed = ReceiptRuntime.options.allowedProductGroups.keywords;
    if (allowed.isNotEmpty && !allowed.toSet().contains(cleaned)) return '';

    return cleaned;
  }

  /// Normalizes all postfix texts to product groups.
  static List<String> normalizeToProductGroups(List<String> postfixTexts) {
    return postfixTexts.map((s) => normalizeToProductGroup(s)).toList();
  }

  /// Normalizes postfix text by comparing multiple alternative recognitions.
  static String? normalizeByAlternativePostfixTexts(
    List<String> altPostfixTexts,
  ) {
    if (altPostfixTexts.isEmpty) return null;

    final normalized = normalizeToProductGroups(altPostfixTexts);
    final mostFrequent = sortByFrequency(normalized);
    final bestResult = mostFrequent.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );

    return bestResult;
  }

  /// Normalizes text by comparing multiple alternative recognitions.
  static String? normalizeByAlternativeTexts(List<String> altTexts) {
    if (altTexts.isEmpty) return null;

    final mostFrequent = sortByFrequency(
      altTexts,
      frequencyCalculator: calculateTruncatedFrequency,
    );
    final bestResult = mostFrequent.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );

    return bestResult;
  }

  /// Like [calculateFrequency], but merges:
  ///  - truncated leading-token alternatives, and
  ///  - single-space-variant alternatives (e.g. "Hello wor ld" -> "Hello world")
  /// into their more frequent counterparts before counting.
  static Map<String, int> calculateTruncatedFrequency(List<String> values) {
    if (values.isEmpty) return const {};

    final normalized = values.map((s) => _normalizeSpaces(s)).toList();
    final trimmed = normalized.map((s) => s.trim()).toList();

    final initialCounts = <String, int>{};
    for (final s in trimmed) {
      initialCounts[s] = (initialCounts[s] ?? 0) + 1;
    }

    final repIndex = <int, int>{};

    for (var i = 0; i < normalized.length; i++) {
      var representative = i;

      final candidateTrimmed = trimmed[i];
      final candidateCount = initialCounts[candidateTrimmed] ?? 0;

      for (var j = 0; j < normalized.length; j++) {
        if (i == j) continue;

        final otherTrimmed = trimmed[j];
        final otherCount = initialCounts[otherTrimmed] ?? 0;

        if (candidateCount >= otherCount) continue;

        bool isPrefixMerge = false;
        bool isSingleSpaceMerge = false;

        if (otherTrimmed.length > candidateTrimmed.length &&
            otherTrimmed.startsWith(candidateTrimmed) &&
            otherTrimmed.length > candidateTrimmed.length) {
          final nextChar = otherTrimmed[candidateTrimmed.length];
          if (nextChar == ' ') {
            isPrefixMerge = true;
          }
        }

        if (!isPrefixMerge) {
          if (candidateTrimmed.length == otherTrimmed.length + 1) {
            for (var k = 0; k < candidateTrimmed.length; k++) {
              if (candidateTrimmed[k] == ' ') {
                final merged =
                    candidateTrimmed.substring(0, k) +
                    candidateTrimmed.substring(k + 1);
                if (merged == otherTrimmed) {
                  isSingleSpaceMerge = true;
                  break;
                }
              }
            }
          }
        }

        if (isPrefixMerge || isSingleSpaceMerge) {
          representative = j;
          break;
        }
      }

      repIndex[i] = representative;
    }

    final remapped = <String>[];
    for (var i = 0; i < values.length; i++) {
      final idx = repIndex[i]!;
      remapped.add(values[idx]);
    }

    return calculateFrequency(remapped);
  }

  /// Map of each unique alternative text to its percentage frequency.
  static Map<String, int> calculateFrequency(List<String> values) {
    if (values.isEmpty) return const {};

    final total = values.length;
    final counts = <String, int>{};
    for (final t in values) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final result = <String, int>{};
    counts.forEach((k, v) => result[k] = ((v / total) * 100).round());
    return result;
  }

  /// Sorts a list of strings by frequency of occurrence in ascending order.
  static List<String> sortByFrequency(
    List<String> values, {
    Map<String, int> Function(List<String> values)? frequencyCalculator,
  }) {
    final freq = (frequencyCalculator ?? calculateFrequency)(values);
    final entries = freq.entries.toList();
    entries.sort((a, b) => a.value.compareTo(b.value));
    return entries.map((e) => e.key).toList();
  }

  /// Returns the best fuzzy match score (0–100) between two strings.
  /// Uses simple, partial and token-set ratios for substring and token-based matching.
  static int similarity(String a, String b) {
    final aNoSpaces = a.replaceAll(_allSpaces, '');
    final bNoSpaces = b.replaceAll(_allSpaces, '');
    final ratios = [
      ratio(aNoSpaces, bNoSpaces),
      partialRatio(aNoSpaces, bNoSpaces),
      tokenSetRatio(aNoSpaces, bNoSpaces),
    ];
    return ratios.reduce(max);
  }

  /// Returns a merge-friendly similarity in [0,1].
  /// Wraps [similarity] (0–100) and scales for thresholding in grouping/merging.
  static double stringSimilarity(String a, String b) {
    return similarity(a, b) / 100.0;
  }

  /// Tokenizes for matching; lowercase, diacritic-free, alnum-only.
  static Set<String> tokensForMatch(String s) {
    final n = _normalizeSpaces(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return n.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
  }

  /// Returns a simple specificity score favoring longer, richer strings.
  static int specificity(String s) {
    final t = tokensForMatch(s);
    final chars = t.join().length;
    return t.length * 10 + chars;
  }

  /// Remove all Unicode whitespace and lowercase for stable lookup keys.
  static String normalizeKey(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// Converts fullwidth characters to halfwidth equivalents.
  /// Fullwidth ASCII (U+FF01-U+FF5E) -> halfwidth (U+0021-U+007E)
  /// Fullwidth space (U+3000) -> ASCII space
  /// Fullwidth yen sign (U+FFE5) -> halfwidth yen sign (U+00A5)
  static String normalizeFullWidth(String s) => String.fromCharCodes(
    s.runes.map(
      (code) => switch (code) {
        >= 0xFF01 && <= 0xFF5E => code - 0xFEE0,
        0x3000 => 0x20,
        0xFFE5 => 0x00A5,
        _ => code,
      },
    ),
  );
}
