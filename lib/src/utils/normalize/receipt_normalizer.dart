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

  /// Filters out alternatives that are just leading tokens of longer variants.
  static List<String> _filterTruncatedAlternatives(List<String> alternatives) {
    final alts = alternatives.map((s) => _normalizeSpaces(s)).toList();
    if (alts.length <= 1) return alts;

    final filtered = <String>[];
    for (final candidate in alts) {
      bool isTruncated = false;
      for (final other in alts) {
        if (other.length > candidate.length) {
          final candidateTrimmed = candidate.trim();
          final otherTrimmed = other.trim();
          if (otherTrimmed.startsWith(candidateTrimmed) &&
              otherTrimmed.length > candidateTrimmed.length) {
            final nextChar = otherTrimmed[candidateTrimmed.length];
            if (nextChar == ' ') {
              isTruncated = true;
              break;
            }
          }
        }
      }
      if (!isTruncated) {
        filtered.add(candidate);
      }
    }

    return filtered.isEmpty ? alts : filtered;
  }

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

    final mostFrequent = sortByFrequency(altTexts);
    final bestResult = mostFrequent.lastWhere(
      (s) => s.isNotEmpty,
      orElse: () => '',
    );

    return bestResult;
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
  static List<String> sortByFrequency(List<String> values) {
    final entries = calculateFrequency(values).entries.toList();
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
}
