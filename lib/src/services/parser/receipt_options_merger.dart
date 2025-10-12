import 'package:receipt_recognition/src/services/parser/index.dart';

/// How user config should interact with built-in defaults.
enum MergePolicy {
  /// Keep defaults and add/override with user config (defaults ∪ user).
  extend,

  /// Ignore defaults completely and use only user config.
  replace,
}

/// Utilities to create effective options from user input + defaults.
final class ReceiptOptionsMerger {
  /// Returns options built solely from built-in defaults (no user overrides).
  static ReceiptOptions defaults() => withDefaults(ReceiptOptions.empty());

  /// Build options using **only** user input (no defaults).
  static ReceiptOptions userOnly(ReceiptOptions? opts) {
    final u = opts ?? ReceiptOptions.empty();
    return ReceiptOptions(
      storeNames: u.storeNames,
      totalLabels: u.totalLabels,
      ignoreKeywords: u.ignoreKeywords,
      stopKeywords: u.stopKeywords,
      foodKeywords: u.foodKeywords,
      nonFoodKeywords: u.nonFoodKeywords,
      discountKeywords: u.discountKeywords,
      depositKeywords: u.depositKeywords,
    );
  }

  /// Build effective options by merging user [opts] with built-in defaults from [ReceiptPatterns].
  /// - extend: defaults ∪ user (user wins on duplicates)
  /// - replace: only user (ignore defaults)
  static ReceiptOptions withDefaults(
    ReceiptOptions? opts, {
    MergePolicy storeNames = MergePolicy.extend,
    MergePolicy totalLabels = MergePolicy.extend,
    MergePolicy ignoreKeywords = MergePolicy.extend,
    MergePolicy stopKeywords = MergePolicy.extend,
    MergePolicy foodKeywords = MergePolicy.extend,
    MergePolicy nonFoodKeywords = MergePolicy.extend,
    MergePolicy discountKeywords = MergePolicy.extend,
    MergePolicy depositKeywords = MergePolicy.extend,
  }) {
    final user = opts ?? ReceiptOptions.empty();
    return ReceiptOptions(
      storeNames: _dmMerge(
        user.storeNames,
        ReceiptPatterns.storeNames,
        storeNames,
      ),
      totalLabels: _dmMerge(
        user.totalLabels,
        ReceiptPatterns.sumLabels,
        totalLabels,
      ),
      ignoreKeywords: _ksMerge(
        user.ignoreKeywords,
        ReceiptPatterns.ignoreKeywords,
        ignoreKeywords,
      ),
      stopKeywords: _ksMerge(
        user.stopKeywords,
        ReceiptPatterns.stopKeywords,
        stopKeywords,
      ),
      foodKeywords: _ksMerge(
        user.foodKeywords,
        ReceiptPatterns.foodKeywords,
        foodKeywords,
      ),
      nonFoodKeywords: _ksMerge(
        user.nonFoodKeywords,
        ReceiptPatterns.nonFoodKeywords,
        nonFoodKeywords,
      ),
      discountKeywords: _ksMerge(
        user.discountKeywords,
        ReceiptPatterns.discountKeywords,
        discountKeywords,
      ),
      depositKeywords: _ksMerge(
        user.depositKeywords,
        ReceiptPatterns.depositKeywords,
        depositKeywords,
      ),
    );
  }

  /// Merge a user [KeywordSet] with defaults according to [p].
  static KeywordSet _ksMerge(KeywordSet u, RegExp def, MergePolicy p) {
    if (p == MergePolicy.replace) return u;
    return KeywordSet.fromList(_unionKeywords(u, def));
  }

  /// Merge a user [DetectionMap] with defaults according to [p].
  static DetectionMap _dmMerge(DetectionMap u, RegExp def, MergePolicy p) {
    if (p == MergePolicy.replace) return u;
    final merged = <String, String>{};
    merged.addAll(
      _extractAlternatives(
        def,
      ).asMap().map((_, k) => MapEntry(k.toLowerCase(), k)),
    );
    merged.addAll(u.mapping);
    return DetectionMap.fromMap(merged);
  }

  /// Extract plain alternatives from a `(a|b|c)` style regex pattern.
  static List<String> _extractAlternatives(RegExp rx) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(rx.pattern);
    if (m == null) return const [];
    return m
        .group(1)!
        .split('|')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Merge user KeywordSet keywords with defaults from regex.
  static List<String> _unionKeywords(KeywordSet user, RegExp defaults) {
    final out = <String>{...user.keywords};
    out.addAll(_extractAlternatives(defaults));
    return out.toList();
  }
}
