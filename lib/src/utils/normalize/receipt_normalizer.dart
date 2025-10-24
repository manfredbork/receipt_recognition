import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/src/utils/logging/index.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Utility for normalizing and standardizing recognized text from receipts.
///
/// Provides methods to unify OCR variants by removing diacritics, correcting
/// spacing, and trimming noisy endings such as trailing price patterns. Ranking
/// prefers the most frequent variant first, then applies heuristic tie-breakers.
final class ReceiptNormalizer {
  /// Matches size tokens like '250g', '330 ml', '1l'.
  static final RegExp _sizeToken = RegExp(
    r'\b\d+\s*(?:[a-z]{1,3}|ml|l|kg|g)\b',
    caseSensitive: false,
  );

  /// Matches trailing price-like tails for grouping key stripping.
  static final RegExp _stripPriceTail = RegExp(r'\s*\d+[.,]?\d{2,3}.*\$');

  /// Finds number–unit splits to glue (e.g., '250 g' -> '250g').
  static final RegExp _numberUnitSplit = RegExp(r'(\d+)\s+([a-z])\b');

  /// Matches punctuation dots and commas to strip for canonical key.
  static final RegExp _punctDotsCommas = RegExp(r'[.,]');

  /// Matches runs of whitespace.
  static final RegExp _spacesRun = RegExp(r'\s+');

  /// Matches non-alphanumeric chars after lowercasing for signatures.
  static final RegExp _nonAlnumLower = RegExp(r'[^a-z0-9]');

  /// Detects glued number–unit tokens (e.g., '250g').
  static final RegExp _gluedNumberUnit = RegExp(r'\d+[a-zA-Z]\b');

  /// A single ASCII space matcher for counting spaces.
  static final RegExp _singleSpace = RegExp(' ');

  /// Captures leading text and trailing price-like tail.
  static final RegExp _priceTail = RegExp(r'(.*\S)(\s*\d+[.,]?\d{2,3}.*)');

  /// Matches explicit euro amounts like '1,99 EURO'.
  static final RegExp _euroAmount = RegExp(r'(\s*\d+[.,]?\d{2}\sEURO?)');

  /// Unicode combining mark ranges (NFD) to strip diacritics.
  static final RegExp _combiningMark = RegExp(
    r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\uFE20-\uFE2F]',
  );

  /// All common Unicode whitespace characters.
  static final RegExp _allSpaces = RegExp(
    r'[\u0009-\u000D\u0020\u0085\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
  );

  /// Normalizes text by comparing multiple alternative recognitions.
  static String? normalizeByAlternativeTexts(List<String> alternativeTexts) {
    ReceiptLogger.log('norm.in', {
      'n': alternativeTexts.length,
      'alts': alternativeTexts,
    });

    if (alternativeTexts.isEmpty) {
      ReceiptLogger.log('norm.out', {'result': null, 'why': 'empty'});
      return null;
    }

    final lengths = alternativeTexts.map((s) => s.length).toList();
    final maxLen = lengths.fold<int>(0, (u, v) => v > u ? v : u);
    final minKeep = maxLen ~/ 2;
    final filteredTexts =
        alternativeTexts.where((f) => f.length > minKeep).toList();

    final Map<String, List<String>> buckets = {};
    for (final t in filteredTexts) {
      final key = _canonicalGroupingKey(t);
      (buckets[key] ??= <String>[]).add(t);
    }
    if (buckets.isEmpty) {
      ReceiptLogger.log('norm.out', {'result': null, 'why': 'no-buckets'});
      return null;
    }

    final bestKey =
        buckets.entries
            .reduce((a, b) => a.value.length >= b.value.length ? a : b)
            .key;
    final candidates = buckets[bestKey]!;

    ReceiptLogger.log('norm.bucket', {
      'count': buckets.length,
      'sizes': buckets.map((k, v) => MapEntry(k, v.length)),
      'bestKey': bestKey,
      'cands': candidates,
    });

    bool hasSizeToken(String s) => _sizeToken.hasMatch(s);

    final Map<String, int> freq = {};
    for (final s in candidates) {
      freq[s] = (freq[s] ?? 0) + 1;
    }

    int cmp(String a, String b) {
      final fa = freq[a] ?? 0;
      final fb = freq[b] ?? 0;
      if (fa != fb) return fb - fa;

      final aHasSize = hasSizeToken(a) ? 1 : 0;
      final bHasSize = hasSizeToken(b) ? 1 : 0;
      if (aHasSize != bHasSize) return bHasSize - aHasSize;

      final ad = _hasDiacritics(a) ? 1 : 0;
      final bd = _hasDiacritics(b) ? 1 : 0;
      if (ad != bd) return ad - bd;

      if (a.length != b.length) return a.length - b.length;

      final aspc = _spaceRunCount(a);
      final bspc = _spaceRunCount(b);
      if (aspc != bspc) return aspc - bspc;

      return a.compareTo(b);
    }

    candidates.sort(cmp);
    final mostFrequent = candidates.first;
    ReceiptLogger.log('norm.rank', {
      'chosen': mostFrequent,
      'ranked': candidates,
    });

    final spaced = normalizeSpecialSpaces(mostFrequent, filteredTexts);

    ReceiptLogger.log('norm.out', {'result': spaced});
    return spaced;
  }

  /// Returns a canonical, diacritic-free key for comparing OCR variants.
  static String canonicalKey(String input) {
    final nfd = unorm.nfd(input);
    final noMarks = nfd.replaceAll(_combiningMark, '');
    return noMarks.toLowerCase().replaceAll(_allSpaces, ' ').trim();
  }

  /// Internal canonical key for grouping that removes price tails and joins number–unit splits.
  static String _canonicalGroupingKey(String input) {
    final base = canonicalKey(input);
    final noTail = base.replaceFirst(_stripPriceTail, '');
    final glued = noTail.replaceAll(_numberUnitSplit, r'$1$2');
    final noPunct = glued.replaceAll(_punctDotsCommas, '');
    return noPunct.replaceAll(_spacesRun, ' ').trim();
  }

  /// Removes trailing price-like numeric patterns while leaving normal text intact.
  static String normalizeTail(String value) {
    final hadPriceTail =
        _priceTail.hasMatch(value) && !_euroAmount.hasMatch(value);
    if (!hadPriceTail) return value;
    final stripped =
        value.replaceAllMapped(_priceTail, (m) => '${m[1]}').trim();
    return stripped;
  }

  /// Normalizes spaces by comparing the most frequent text with its peers.
  static String normalizeSpecialSpaces(
    String mostFrequent,
    List<String> allAlternatives,
  ) {
    String sig(String s) => canonicalKey(s).replaceAll(_nonAlnumLower, '');
    final target = sig(mostFrequent);
    final sameSignature =
        allAlternatives.where((t) => sig(t) == target).toList();
    if (sameSignature.isEmpty) {
      ReceiptLogger.log('norm.spaces', {
        'target': mostFrequent,
        'picked': mostFrequent,
        'reason': 'no-same-signature',
      });
      return mostFrequent;
    }

    final Map<String, int> freq = {};
    for (final s in sameSignature) {
      freq[s] = (freq[s] ?? 0) + 1;
    }

    bool hasDiacritics(String s) {
      final nfd = unorm.nfd(s);
      return _combiningMark.hasMatch(nfd);
    }

    sameSignature.sort((a, b) {
      final fa = freq[a] ?? 0;
      final fb = freq[b] ?? 0;
      if (fa != fb) return fb - fa;

      final ad = hasDiacritics(a) ? 1 : 0;
      final bd = hasDiacritics(b) ? 1 : 0;
      if (ad != bd) return ad - bd;

      final aGlued = _gluedNumberUnit.hasMatch(a) ? 1 : 0;
      final bGlued = _gluedNumberUnit.hasMatch(b) ? 1 : 0;
      if (aGlued != bGlued) return bGlued - aGlued;

      final aSpaces = _singleSpace.allMatches(a).length;
      final bSpaces = _singleSpace.allMatches(b).length;
      if (aSpaces != bSpaces) return aSpaces - bSpaces;

      if (a.length != b.length) return a.length - b.length;

      return a.compareTo(b);
    });

    final picked = sameSignature.first;
    ReceiptLogger.log('norm.spaces', {
      'target': mostFrequent,
      'picked': picked,
      'cands': sameSignature,
    });
    return picked;
  }

  /// Sorts a list of strings by frequency of occurrence in ascending order.
  static List<String> sortByFrequency(List<String> values) {
    final Map<String, int> freq = {};
    for (final v in values) {
      freq[v] = (freq[v] ?? 0) + 1;
    }
    final entries =
        freq.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
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
    final n = canonicalKey(s).replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    return n.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toSet();
  }

  /// Returns a simple specificity score favoring longer, richer strings.
  static int specificity(String s) {
    final t = tokensForMatch(s);
    final chars = t.join().length;
    return t.length * 10 + chars;
  }

  /// Returns true if the string contains combining diacritic marks.
  static bool _hasDiacritics(String s) {
    final nfd = unorm.nfd(s);
    return _combiningMark.hasMatch(nfd);
  }

  /// Counts runs of whitespace in a string.
  static int _spaceRunCount(String s) {
    return _spacesRun.allMatches(s).length;
  }
}
