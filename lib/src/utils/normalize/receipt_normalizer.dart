import 'dart:math';

import 'package:fuzzywuzzy/fuzzywuzzy.dart';
import 'package:receipt_recognition/receipt_recognition.dart';
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
  static final RegExp _stripPriceTail = RegExp(r'\s*\d+[.,]?\d{2,3}.*$');

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

  /// A single white space matcher for counting spaces.
  static final RegExp _singleSpace = RegExp(r'\s');

  /// Unicode combining mark ranges (NFD) to strip diacritics.
  static final RegExp _combiningMark = RegExp(
    r'[\u0300-\u036f\u1ab0-\u1aff\u1dc0-\u1dff\u20d0-\u20ff\uFE20-\uFE2F]',
  );

  /// All common Unicode whitespace characters.
  static final RegExp _allSpaces = RegExp(
    r'[\u0009-\u000D\u0020\u0085\u00A0\u1680\u180E\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
  );

  /// Price-like tail (handles 1,99 / 12.345,67 / unicode seps / €|eur|euro|e / optional x quantity)
  static final RegExp _priceTail = RegExp(
    '(.*\\S)\\s*\\d{1,3}(?:[ .’\\\']\\d{3})*\\s*[.,‚،٫·]\\s*\\d{2,3}(?:\\s*(?:€|eur|euro|e))?(?:\\s*[x×]\\s*\\d*)?[\\s\\S]*',
    caseSensitive: false,
  );

  /// Standalone trailing int (e.g., "... 9")
  static final RegExp _trailingStandaloneInt = RegExp(
    '(.*\\S)\\s+(\\d+)\\s*\\\$',
  );

  /// Dangling "x"/"×"
  static final RegExp _danglingTimes = RegExp(
    '(.*\\S)\\s+[x×]\\s*\\\$',
    caseSensitive: false,
  );

  /// Dangling currency
  static final RegExp _danglingCurrency = RegExp(
    '(.*\\S)\\s+(?:€|eur|euro|e)\\s*\\\$',
    caseSensitive: false,
  );

  /// Collapse all Unicode spaces to a normal space first.
  static String _normalizeSpaces(String s) =>
      s.replaceAll(_allSpaces, ' ').trim();

  /// Removes trailing price-like numeric patterns, while leaving normal text intact.
  static String normalizeTail(String value) {
    final v = _normalizeSpaces(value);

    final m1 = _priceTail.firstMatch(v);
    if (m1 != null) return m1.group(1)!.trim();

    final m2 = _trailingStandaloneInt.firstMatch(v);
    if (m2 != null) return m2.group(1)!.trim();

    final m3 = _danglingTimes.firstMatch(v);
    if (m3 != null) return m3.group(1)!.trim();

    final m4 = _danglingCurrency.firstMatch(v);
    if (m4 != null) return m4.group(1)!.trim();

    return v;
  }

  /// Normalizes text by comparing multiple alternative recognitions.
  /// Example: ['COKE  ZERO', 'COKE ZERO', 'COKEZ ERO'] -> 'COKE ZERO'
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

    final spaceNormalized = _removeErroneousSingleSpaces(filteredTexts);
    final corrected = _applyOcrCorrection(spaceNormalized);
    final nonTruncated = _filterTruncatedAlternatives(corrected);

    ReceiptLogger.log('norm.after_truncation_filter', {
      'before': corrected.length,
      'after': nonTruncated.length,
      'removed': corrected.where((t) => !nonTruncated.contains(t)).toList(),
    });

    final Map<String, List<String>> buckets = {};
    for (final t in nonTruncated) {
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

  /// Removes erroneous single spaces by replacing texts that equal another text
  /// when exactly one space is removed.
  /// Example: ['Weide milch', 'Weidemilch'] -> ['Weidemilch', 'Weidemilch']
  static List<String> _removeErroneousSingleSpaces(List<String> alternatives) {
    if (alternatives.length < 2) return alternatives;

    final corrected = <String>[];

    for (final text in alternatives) {
      String? matchedWithoutSpace;

      for (final other in alternatives) {
        if (other == text) continue;

        final withoutSpace = _tryRemovingSingleSpace(text, other);
        if (withoutSpace != null) {
          matchedWithoutSpace = other;
          ReceiptLogger.log('space.remove', {
            'original': text,
            'corrected': other,
            'removed_space': true,
          });
          break;
        }
      }

      corrected.add(matchedWithoutSpace ?? text);
    }

    return corrected;
  }

  /// Tries to find if removing exactly one space from [textWithSpace] equals [textWithoutSpace].
  /// Returns the match if found, null otherwise.
  /// Example: tryRemovingSingleSpace('Weide milch', 'Weidemilch') -> 'Weidemilch'
  static String? _tryRemovingSingleSpace(
    String textWithSpace,
    String textWithoutSpace,
  ) {
    final spacesInFirst = ' '.allMatches(textWithSpace).length;
    final spacesInSecond = ' '.allMatches(textWithoutSpace).length;

    if (spacesInFirst != spacesInSecond + 1) return null;

    for (int i = 0; i < textWithSpace.length; i++) {
      if (textWithSpace[i] == ' ') {
        final withoutThisSpace =
            textWithSpace.substring(0, i) + textWithSpace.substring(i + 1);

        if (withoutThisSpace == textWithoutSpace) {
          return textWithoutSpace;
        }
      }
    }

    return null;
  }

  /// Applies OCR error correction by comparing alternatives and replacing commonly
  /// confused characters (digits/special chars) with normal letters when appropriate.
  /// Only corrects alternatives with percentage occurrences below stabilityThreshold.
  /// Example: ['8io Weidemilch', 'Bio Weidemilch'] -> ['Bio Weidemilch', 'Bio Weidemilch']
  static List<String> _applyOcrCorrection(List<String> alternatives) {
    if (alternatives.length < 2) return alternatives;

    final total = alternatives.length;
    final counts = <String, int>{};
    for (final text in alternatives) {
      counts[text] = (counts[text] ?? 0) + 1;
    }
    final percentages = <String, int>{};
    counts.forEach((k, v) => percentages[k] = ((v / total) * 100).round());

    final confidenceThreshold =
        ReceiptRuntime.options.tuning.optimizerConfidenceThreshold;
    final stabilityThreshold =
        ReceiptRuntime.options.tuning.optimizerStabilityThreshold;

    final corrected = <String>[];

    for (final text in alternatives) {
      final percentage = percentages[text] ?? 0;
      final percConfThreshold =
          alternatives.length <= 2 && percentage >= confidenceThreshold;
      final percStabThreshold =
          alternatives.length > 2 && percentage >= stabilityThreshold;

      if (percConfThreshold || percStabThreshold) {
        corrected.add(text);
        continue;
      }

      final chars = text.split('');
      final ocrAlternatives = alternatives.where((t) => t != text).toList();

      for (int i = 0; i < chars.length; i++) {
        final char = chars[i];

        if (_isNormalLetter(char) || _isWhitespace(char)) continue;

        for (final other in ocrAlternatives) {
          if (other.length > i) {
            final otherChar = other[i];

            if (_isNormalLetter(otherChar) &&
                _isSimilarExceptPosition(text, other, i)) {
              if (i + 1 < chars.length &&
                  chars[i + 1].toLowerCase() == otherChar.toLowerCase()) {
                continue;
              }
              chars[i] = otherChar;
              ReceiptLogger.log('ocr.correct', {
                'original': text,
                'pos': i,
                'from': char,
                'to': otherChar,
                'reference': other,
                'percentage': percentage,
                'threshold': stabilityThreshold,
              });
              break;
            }
          }
        }
      }

      corrected.add(chars.join());
    }

    return corrected;
  }

  /// Checks if a character is a "normal" letter (Latin alphabet + common diacritics).
  /// Returns true for: A-Z, a-z, and letters with diacritics (ä, ö, ü, é, à, etc.)
  /// Returns false for: digits, special chars, punctuation
  /// Example: isNormalLetter('O') -> true, isNormalLetter('0') -> false
  static bool _isNormalLetter(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);

    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) {
      return true;
    }

    if ((code >= 192 && code <= 214) ||
        (code >= 216 && code <= 246) ||
        (code >= 248 && code <= 255)) {
      return true;
    }

    if (code >= 256 && code <= 383) {
      return true;
    }

    return false;
  }

  /// Returns true if [ch] is a whitespace character (specifically a single ASCII space).
  static bool _isWhitespace(String ch) =>
      ch.isNotEmpty && _singleSpace.hasMatch(ch);

  /// Checks if two strings are similar except at a specific position.
  /// Example: isSimilarExceptPosition('0blaten', 'Oblaten', 0) -> true
  static bool _isSimilarExceptPosition(String a, String b, int pos) {
    if ((a.length - b.length).abs() > 1) return false;

    final minLen = a.length < b.length ? a.length : b.length;
    int diffs = 0;

    for (int i = 0; i < minLen; i++) {
      if (a[i].toLowerCase() != b[i].toLowerCase()) {
        if (i != pos) diffs++;
        if (diffs > 1) return false;
      }
    }

    return true;
  }

  /// Filters out alternatives that are just leading tokens of longer variants.
  /// Example: ['GOETTERSP.', 'GOETTERSP. WALD'] -> ['GOETTERSP. WALD']
  static List<String> _filterTruncatedAlternatives(List<String> alternatives) {
    if (alternatives.length <= 1) return alternatives;

    final filtered = <String>[];
    for (final candidate in alternatives) {
      bool isTruncated = false;
      for (final other in alternatives) {
        if (other.length > candidate.length) {
          final candidateTrimmed = candidate.trim();
          final otherTrimmed = other.trim();
          if (otherTrimmed.startsWith(candidateTrimmed) &&
              otherTrimmed.length > candidateTrimmed.length) {
            final nextChar = otherTrimmed[candidateTrimmed.length];
            if (nextChar == ' ' || nextChar == '\t') {
              isTruncated = true;
              ReceiptLogger.log('norm.truncated_detected', {
                'truncated': candidate,
                'complete': other,
              });
              break;
            }
          }
        }
      }
      if (!isTruncated) {
        filtered.add(candidate);
      }
    }

    return filtered.isEmpty ? alternatives : filtered;
  }

  /// Returns a canonical, diacritic-free key for comparing OCR variants.
  /// Example: 'Café Latté' -> 'cafe latte'
  static String canonicalKey(String input) {
    final nfd = unorm.nfd(input);
    final noMarks = nfd.replaceAll(_combiningMark, '');
    return noMarks.toLowerCase().replaceAll(_allSpaces, ' ').trim();
  }

  /// Internal canonical key for grouping that removes price tails and joins number–unit splits.
  static String _canonicalGroupingKey(String input) {
    final base = canonicalKey(input);
    final noTail = base.replaceFirst(_stripPriceTail, '');
    final glued = noTail.replaceAllMapped(
      _numberUnitSplit,
      (m) => '${m[1]}${m[2]}',
    );
    final noPunct = glued.replaceAll(_punctDotsCommas, '');
    return noPunct.replaceAll(_spacesRun, ' ').trim();
  }

  /// Normalizes spaces by comparing the most frequent text with its peers.
  /// Example: ['Co ke Zero', 'Coke Zero', 'CokeZero'] -> 'Coke Zero'
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
  /// Example: ['A', 'B', 'A', 'C', 'B', 'A'] -> ['C', 'B', 'A']
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
