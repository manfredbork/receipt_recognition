import 'package:receipt_recognition/src/utils/logging/index.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Utility for normalizing and standardizing recognized text from receipts.
///
/// Provides methods to unify OCR variants by removing diacritics, correcting
/// spacing, and trimming noisy endings such as trailing price patterns.
final class ReceiptNormalizer {
  /// Normalizes text by comparing multiple alternative recognitions.
  ///
  /// Builds consensus across multiple recognitions by:
  /// - Grouping by a price-tail–free canonical key.
  /// - Ranking candidates by their tail-stripped form, preferring strings that
  ///   contain a size token (e.g., "250g", "330 ml"), then no-diacritics, then
  ///   shorter length, then fewer space runs.
  /// - Normalizing spaces against all alternatives and returning the spaced result.
  static String? normalizeByAlternativeTexts(List<String> alternativeTexts) {
    ReceiptLogger.log('norm.in', {
      'n': alternativeTexts.length,
      'alts': alternativeTexts,
    });
    if (alternativeTexts.isEmpty) {
      ReceiptLogger.log('norm.out', {'result': null, 'why': 'empty'});
      return null;
    }

    final Map<String, List<String>> buckets = {};
    for (final t in alternativeTexts) {
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

    bool hasSizeToken(String s) => RegExp(
      r'\b\d+\s*(?:[a-z]{1,3}|ml|l|kg|g)\b',
      caseSensitive: false,
    ).hasMatch(s);

    int cmp(String a, String b) {
      final aa = normalizeTail(a);
      final bb = normalizeTail(b);

      final aHasSize = hasSizeToken(aa) ? 1 : 0;
      final bHasSize = hasSizeToken(bb) ? 1 : 0;
      if (aHasSize != bHasSize) return bHasSize - aHasSize;

      final ad = _hasDiacritics(aa) ? 1 : 0;
      final bd = _hasDiacritics(bb) ? 1 : 0;
      if (ad != bd) return ad - bd;

      if (aa.length != bb.length) return aa.length - bb.length;

      final aspc = _spaceRunCount(aa);
      final bspc = _spaceRunCount(bb);
      if (aspc != bspc) return aspc - bspc;

      return a.compareTo(b);
    }

    candidates.sort(cmp);
    final mostFrequent = candidates.first;
    ReceiptLogger.log('norm.rank', {
      'chosen': mostFrequent,
      'ranked': candidates,
    });

    final bestTailStripped = normalizeTail(mostFrequent);
    final allTailStripped = alternativeTexts.map(normalizeTail).toList();
    final spaced = normalizeSpecialSpaces(bestTailStripped, allTailStripped);

    ReceiptLogger.log('norm.out', {'result': spaced});
    return spaced;
  }

  /// Returns a canonical, diacritic-free key for comparing OCR variants.
  ///
  /// Lowercases, removes combining marks, and collapses all Unicode spaces.
  static String canonicalKey(String input) {
    final nfd = unorm.nfd(input);
    final noMarks = nfd.replaceAll(_combiningMark, '');
    return noMarks.toLowerCase().replaceAll(_allSpaces, ' ').trim();
  }

  /// Internal canonical key for grouping that removes price tails and joins number–unit splits.
  static String _canonicalGroupingKey(String input) {
    final base = canonicalKey(input);
    final noTail = base.replaceFirst(RegExp(r'\s*\d+[.,]?\d{2,3}.*$'), '');
    final glued = noTail.replaceAll(RegExp(r'(\d+)\s+([a-z])\b'), r'$1$2');
    final noPunct = glued.replaceAll(RegExp(r'[.,]'), '');
    return noPunct.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Removes trailing price-like numeric patterns; leaves normal text intact.
  static String normalizeTail(String value) {
    final priceTail = RegExp(r'(.*\S)(\s*\d+[.,]?\d{2,3}.*)');
    final euroAmount = RegExp(r'(\s*\d+[.,]?\d{2}\sEURO?)');
    final hadPriceTail =
        priceTail.hasMatch(value) && !euroAmount.hasMatch(value);
    if (!hadPriceTail) return value;
    final stripped = value.replaceAllMapped(priceTail, (m) => '${m[1]}').trim();
    return stripped;
  }

  /// Normalizes spaces by comparing the most frequent text with its peers.
  ///
  /// If another variant has the same alphanumeric sequence and is preferred by
  /// ASCII→glued-number-unit→fewer-spaces→shorter ordering, it is used.
  static String normalizeSpecialSpaces(
    String mostFrequent,
    List<String> allAlternatives,
  ) {
    String sig(String s) =>
        canonicalKey(s).replaceAll(RegExp(r'[^a-z0-9]'), '');
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

    bool hasDiacritics(String s) {
      final nfd = unorm.nfd(s);
      return _combiningMark.hasMatch(nfd);
    }

    sameSignature.sort((a, b) {
      final ad = hasDiacritics(a) ? 1 : 0;
      final bd = hasDiacritics(b) ? 1 : 0;
      if (ad != bd) return ad - bd;

      final aGlued = RegExp(r'\d+[a-zA-Z]\b').hasMatch(a) ? 1 : 0;
      final bGlued = RegExp(r'\d+[a-zA-Z]\b').hasMatch(b) ? 1 : 0;
      if (aGlued != bGlued) return bGlued - aGlued;

      final aSpaces = RegExp(' ').allMatches(a).length;
      final bSpaces = RegExp(' ').allMatches(b).length;
      if (aSpaces != bSpaces) return aSpaces - bSpaces;

      return a.length - b.length;
    });

    final picked = sameSignature.first;
    ReceiptLogger.log('norm.spaces', {
      'target': mostFrequent,
      'picked': picked,
      'cands': sameSignature,
    });
    return picked.length < mostFrequent.length ? picked : mostFrequent;
  }

  /// Sorts a list of strings by their frequency of occurrence in ascending order.
  static List<String> sortByFrequency(List<String> values) {
    final Map<String, int> freq = {};
    for (final v in values) {
      freq[v] = (freq[v] ?? 0) + 1;
    }
    final entries =
        freq.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    return entries.map((e) => e.key).toList();
  }

  /// Checks whether a string contains combining diacritic marks.
  static bool _hasDiacritics(String s) {
    final nfd = unorm.nfd(s);
    return _combiningMark.hasMatch(nfd);
  }

  /// Counts runs of whitespace.
  static int _spaceRunCount(String s) {
    return RegExp(r'\s+').allMatches(s).length;
  }

  /// Combining mark detection regex.
  static final RegExp _combiningMark = RegExp(
    r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\uFE20-\uFE2F]',
  );

  /// All common Unicode whitespace characters.
  static final RegExp _allSpaces = RegExp(
    r'[\u0009-\u000D\u0020\u0085\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
  );
}
